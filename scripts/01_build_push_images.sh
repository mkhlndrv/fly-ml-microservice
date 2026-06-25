#!/usr/bin/env bash
# Build the internal classifier image and push it to the Fly private registry
# (registry.fly.io/$IMAGES_APP:classifier-v1). The public API is built later by
# `fly deploy`; only the sidecar needs a pre-built image.
set -euo pipefail

cd "$(dirname "$0")/.."

: "${IMAGES_APP:?Set IMAGES_APP, e.g. export IMAGES_APP=<your-images-app>}"

FLY_ORG="${FLY_ORG:-harbour-ml-solution-course}"
CLASSIFIER_IMAGE_TAG="${CLASSIFIER_IMAGE_TAG:-classifier-v1}"
CLASSIFIER_IMAGE="registry.fly.io/$IMAGES_APP:$CLASSIFIER_IMAGE_TAG"

if ! command -v fly >/dev/null 2>&1; then
  echo "fly CLI is not installed: https://fly.io/docs/flyctl/install/" >&2
  exit 1
fi
if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is not installed or not running." >&2
  exit 1
fi

fly auth whoami >/dev/null

# Create the registry app once if it does not exist yet.
if ! fly apps list --org "$FLY_ORG" --quiet | awk '{print $1}' | grep -qx "$IMAGES_APP"; then
  fly apps create "$IMAGES_APP" --org "$FLY_ORG" --yes
fi

fly auth docker

echo "Building classifier_service -> $CLASSIFIER_IMAGE"
docker build --platform linux/amd64 -t "$CLASSIFIER_IMAGE" ./classifier_service
docker push "$CLASSIFIER_IMAGE"
docker manifest inspect "$CLASSIFIER_IMAGE" >/dev/null

echo
echo "Pushed: $CLASSIFIER_IMAGE"
echo "Now deploy with: ./scripts/02_deploy_fly.sh"
