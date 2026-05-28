#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

docker compose -f docker-compose.dev.yml exec frappe \
  bash -c 'bench --site "$SITE_NAME" migrate'
