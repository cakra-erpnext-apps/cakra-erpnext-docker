#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.prod.yml}"
PROJECT_NAME="${COMPOSE_PROJECT_NAME:-erp_oak}"
SITE_NAME="${SITE_NAME:-app.oakdepo.com}"
BUILD_APPS_DEFAULT="frappe,erpnext,hrms,crm,helpdesk,raven,gameplan,telephony"
BUILD_APPS_VALUE="${BUILD_APPS:-$BUILD_APPS_DEFAULT}"
RESTART_SERVICES="backend websocket queue-short queue-default queue-long scheduler nginx"
DO_GIT_PULL="${DO_GIT_PULL:-0}"
DO_BUILD="${DO_BUILD:-0}"
NO_CACHE="${NO_CACHE:-0}"
DO_BACKUP="${DO_BACKUP:-0}"

log() { printf '\n[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
run() { log "+ $*"; "$@"; }

usage() {
  cat <<'EOF'
Usage: scripts/prod-update.sh [options]

Safe production update helper for Cakra ERPNext Docker.

Default flow:
  - preflight checks
  - migrate site
  - build frontend assets
  - materialize assets into sites/assets for docker nginx
  - clear caches
  - restart Frappe runtime services + nginx
  - verify health, app routes, and asset serving

Options:
  --pull       git pull before update
  --build      docker compose build before update
  --no-cache   with --build, build without Docker cache
  --backup     run scripts/backup.sh before update
  --help       show this help

Environment overrides:
  SITE_NAME=app.oakdepo.com
  COMPOSE_PROJECT_NAME=cakra_erpnext
  BUILD_APPS=frappe,erpnext,hrms,crm,helpdesk,raven,gameplan,telephony
  COMPOSE_FILE=docker-compose.prod.yml

Examples:
  scripts/prod-update.sh
  scripts/prod-update.sh --pull --build --backup
  scripts/prod-update.sh --build --no-cache
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pull) DO_GIT_PULL=1 ;;
    --build) DO_BUILD=1 ;;
    --no-cache) NO_CACHE=1 ;;
    --backup) DO_BACKUP=1 ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
  shift
done

if [[ ! -f "$COMPOSE_FILE" ]]; then
  echo "Missing $COMPOSE_FILE. Run from repo root or scripts/ directory." >&2
  exit 1
fi

log "Preflight"
run docker compose -p "$PROJECT_NAME" -f "$COMPOSE_FILE" ps

if [[ "$DO_GIT_PULL" == "1" ]]; then
  run git pull --ff-only
fi

if [[ "$DO_BACKUP" == "1" ]]; then
  if [[ ! -x scripts/backup.sh ]]; then
    echo "scripts/backup.sh missing or not executable" >&2
    exit 1
  fi
  run scripts/backup.sh
fi

if [[ "$DO_BUILD" == "1" ]]; then
  if [[ "$NO_CACHE" == "1" ]]; then
    run docker compose -p "$PROJECT_NAME" -f "$COMPOSE_FILE" build --no-cache backend
  else
    run docker compose -p "$PROJECT_NAME" -f "$COMPOSE_FILE" build backend
  fi
  run docker compose -p "$PROJECT_NAME" -f "$COMPOSE_FILE" up -d
fi

log "Migrate, build assets, materialize assets, clear cache"
docker compose -p "$PROJECT_NAME" -f "$COMPOSE_FILE" exec -T \
  -e SITE_NAME="$SITE_NAME" \
  -e BUILD_APPS="$BUILD_APPS_VALUE" \
  -e MATERIALIZE_ASSETS=1 \
  backend bash -lc '
set -euo pipefail
cd /home/frappe/frappe-bench
bench --site "$SITE_NAME" migrate
bench build --apps "$BUILD_APPS"
/usr/local/bin/build-assets.sh
bench --site "$SITE_NAME" clear-cache
bench --site "$SITE_NAME" clear-website-cache
'

log "Restart runtime services and nginx"
run docker compose -p "$PROJECT_NAME" -f "$COMPOSE_FILE" restart $RESTART_SERVICES

log "Wait for backend health"
for i in {1..30}; do
  code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 8 -H "Host: $SITE_NAME" http://127.0.0.1:8088/api/method/ping || true)"
  if [[ "$code" == "200" ]]; then
    echo "ping: 200"
    break
  fi
  echo "ping: $code (retry $i/30)"
  sleep 2
  if [[ "$i" == "30" ]]; then
    echo "Backend health failed" >&2
    exit 1
  fi
done

log "Verify key routes"
for path in /helpdesk /raven /g /assets/frappe/icons/lucide/icons.svg; do
  code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 12 -H "Host: $SITE_NAME" "http://127.0.0.1:8088$path" || true)"
  printf '%-45s %s\n' "$path" "$code"
done

log "Verify current asset manifest entries"
docker compose -p "$PROJECT_NAME" -f "$COMPOSE_FILE" exec -T backend bash -lc '
cd /home/frappe/frappe-bench
python3 - <<PY
import json, urllib.request, os, sys
site=os.environ.get("SITE_NAME", "app.oakdepo.com")
keys=["desk.bundle.css","erpnext.bundle.css","hrms.bundle.css","raven.bundle.css","libs.bundle.js"]
with open("sites/assets/assets.json") as f:
    assets=json.load(f)
for key in keys:
    url=assets.get(key)
    print(f"{key}: {url or 'MISSING'}")
PY
'

log "Done. Browser may need Ctrl+F5 / Disable cache reload."
