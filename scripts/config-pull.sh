#!/usr/bin/env bash
# Pull site_config.json dari container ke host
# Usage: scrip../../config-pull.sh [sitename]

set -euo pipefail
CONFIG_DIR="$(dirname "$0")/../../config"
BACKEND="erp_oak-backend-1"

pull_site() {
  local site="$1"
  local src="/home/frappe/frappe-bench/sites/${site}/site_config.json"
  local dst="$CONFIG_DIR/${site}.json"
  echo "[PULL] $site"
  docker cp "${BACKEND}:${src}" "$dst"
  echo "[OK] $site -> $dst"
}

if [[ $# -gt 0 ]]; then
  pull_site "$1"
else
  for site in app.oakdepo.com app.cakraindo.com; do
    pull_site "$site"
  done
fi
