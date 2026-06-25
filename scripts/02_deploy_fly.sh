#!/usr/bin/env bash
# Generate the Fly config + compose file from the templates and deploy the
# multi-container Machine. Set DRY_RUN=1 to only validate (no Machine created).
set -euo pipefail

cd "$(dirname "$0")/.."

: "${COMPOSE_APP:?Set COMPOSE_APP, e.g. export COMPOSE_APP=<your-compose-app>}"
: "${IMAGES_APP:?Set IMAGES_APP, e.g. export IMAGES_APP=<your-images-app>}"

FLY_ORG="${FLY_ORG:-harbour-ml-solution-course}"
FLY_REGION="${FLY_REGION:-fra}"
CLASSIFIER_IMAGE_TAG="${CLASSIFIER_IMAGE_TAG:-classifier-v1}"
CLASSIFIER_IMAGE="${CLASSIFIER_IMAGE:-registry.fly.io/$IMAGES_APP:$CLASSIFIER_IMAGE_TAG}"
FLY_CONFIG="fly.generated.toml"
FLY_COMPOSE_FILE="docker-compose.fly.yml"

if ! command -v fly >/dev/null 2>&1; then
  echo "fly CLI is not installed: https://fly.io/docs/flyctl/install/" >&2
  exit 1
fi

fly auth whoami >/dev/null
fly auth docker

if ! docker manifest inspect "$CLASSIFIER_IMAGE" >/dev/null 2>&1; then
  echo "Classifier image not found: $CLASSIFIER_IMAGE" >&2
  echo "Run ./scripts/01_build_push_images.sh first." >&2
  exit 1
fi

# Fill the templates (keeps per-student app names out of git).
sed -e "s|__COMPOSE_APP__|$COMPOSE_APP|g" \
    -e "s|__FLY_REGION__|$FLY_REGION|g" \
    fly.toml.template > "$FLY_CONFIG"
sed -e "s|__CLASSIFIER_IMAGE__|$CLASSIFIER_IMAGE|g" \
    docker-compose.fly.yml.template > "$FLY_COMPOSE_FILE"

fly config validate --config "$FLY_CONFIG"

if [[ "${DRY_RUN:-0}" == "1" ]]; then
  echo "DRY_RUN: validated only. Generated $FLY_CONFIG and $FLY_COMPOSE_FILE."
  exit 0
fi

if ! fly apps list --org "$FLY_ORG" --quiet | awk '{print $1}' | grep -qx "$COMPOSE_APP"; then
  fly apps create "$COMPOSE_APP" --org "$FLY_ORG" --yes
fi

echo "Deploying $COMPOSE_APP (classifier=$CLASSIFIER_IMAGE)..."
fly deploy --config "$FLY_CONFIG" --ha=false
fly status --app "$COMPOSE_APP"

echo
echo "Public URL: https://$COMPOSE_APP.fly.dev"
echo "Test with:  ./scripts/03_test.sh https://$COMPOSE_APP.fly.dev"
echo "First start can take 20-60s while Postgres initializes."
