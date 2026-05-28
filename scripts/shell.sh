#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if docker compose -f docker-compose.dev.yml ps --status running --services | grep -qx frappe; then
  docker compose -f docker-compose.dev.yml exec frappe bash
else
  docker compose -f docker-compose.dev.yml run --rm --entrypoint bash frappe
fi
