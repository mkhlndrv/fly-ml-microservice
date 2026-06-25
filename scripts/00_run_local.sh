#!/usr/bin/env bash
# Build and run the full stack locally with Docker Compose, then smoke-test it.
set -euo pipefail

cd "$(dirname "$0")/.."

docker compose -f docker-compose.local.yml up -d --build

echo "Waiting for the API to become ready..."
until curl -fs http://127.0.0.1:8013/ready >/dev/null 2>&1; do
  sleep 1
done

./scripts/03_test.sh http://127.0.0.1:8013

echo
echo "Public API docs:        http://127.0.0.1:8013/docs"
echo "Classifier sidecar docs: http://127.0.0.1:8014/docs"
echo "Postgres local port:    127.0.0.1:5434"
echo
echo "Stop with: docker compose -f docker-compose.local.yml down"
