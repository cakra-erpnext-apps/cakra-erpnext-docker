#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

docker compose -f docker-compose.prod.yml exec backend \
  bash -c 'bench --site "$SITE_NAME" migrate \
    && bench --site "$SITE_NAME" clear-cache \
    && bench --site "$SITE_NAME" clear-website-cache'
