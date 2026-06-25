#!/usr/bin/env bash
# Smoke-test a running deployment (local or Fly).
#   ./scripts/03_test.sh http://127.0.0.1:8013
#   ./scripts/03_test.sh https://<your-compose-app>.fly.dev
set -euo pipefail

BASE_URL="${1:-${BASE_URL:-}}"
if [[ -z "$BASE_URL" && -n "${COMPOSE_APP:-}" ]]; then
  BASE_URL="https://$COMPOSE_APP.fly.dev"
fi
if [[ -z "$BASE_URL" ]]; then
  echo "Usage: ./scripts/03_test.sh https://<app>.fly.dev" >&2
  exit 1
fi
BASE_URL="${BASE_URL%/}"

wait_for_json() {
  local path="$1" out
  out="$(mktemp)"
  for attempt in {1..45}; do
    if curl -fsS "$BASE_URL$path" > "$out"; then
      python3 -m json.tool < "$out"; rm -f "$out"; return 0
    fi
    echo "Waiting for $BASE_URL$path ($attempt/45)..." >&2
    sleep 2
  done
  rm -f "$out"; echo "Not ready: $BASE_URL$path" >&2; return 1
}

echo "## /health"; wait_for_json "/health"
echo "## /ready";  wait_for_json "/ready"

echo "## /predict (the assignment's manual check)"
curl -fsS -X POST "$BASE_URL/predict" \
  -H "Content-Type: application/json" \
  -d '{"text":"Hello"}' | python3 -m json.tool

echo "## /predict (a more bot-like message)"
curl -fsS -X POST "$BASE_URL/predict" \
  -H "Content-Type: application/json" \
  -d '{"text":"As an AI language model, I am happy to assist you with any task."}' | python3 -m json.tool

echo "## /predictions/recent (proves results are stored in the database)"
curl -fsS "$BASE_URL/predictions/recent?limit=3" | python3 -m json.tool
