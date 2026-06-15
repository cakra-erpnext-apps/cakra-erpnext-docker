#!/usr/bin/env bash
# Push site_config.json dari host ke container
# Usage: scrip../../config-push.sh [sitename]
# Example: scrip../../config-push.sh app.oakdepo.com
#          scrip../../config-push.sh  (push semua)

set -euo pipefail
CONFIG_DIR="$(dirname "$0")/../../config"
BACKEND="erp_oak-backend-1"

push_site() {
  local site="$1"
  local src="$CONFIG_DIR/${site}.json"
  local dst="/home/frappe/frappe-bench/sites/${site}/site_config.json"
  if [[ ! -f "$src" ]]; then
    echo "[SKIP] $src not found"
    return
  fi
  echo "[PUSH] $site"
  docker cp "$src" "${BACKEND}:${dst}"
  docker exec "$BACKEND" bash -lc "cd /home/frappe/frappe-bench && bench --site $site clear-cache" 2>/dev/null || true
  echo "[OK] $site"
}

if [[ $# -gt 0 ]]; then
  push_site "$1"
else
  for f in "$CONFIG_DIR"/*.json; do
    site="$(basename "$f" .json)"
    push_site "$site"
  done
fi
