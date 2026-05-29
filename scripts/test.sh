#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

APP="${1:-erpnext_custom}"

docker compose -f docker-compose.dev.yml exec frappe \
  bash -c "bench --site \"\$SITE_NAME\" run-tests --app \"$APP\" \
    && bench --site \"\$SITE_NAME\" clear-cache \
    && bench --site \"\$SITE_NAME\" clear-website-cache"
