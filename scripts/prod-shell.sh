#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

SERVICE="${1:-backend}"

if docker compose -f docker-compose.prod.yml ps --status running --services | grep -qx "$SERVICE"; then
  docker compose -f docker-compose.prod.yml exec "$SERVICE" bash
else
  docker compose -f docker-compose.prod.yml run --rm --entrypoint bash "$SERVICE"
fi
