#!/usr/bin/env bash
# prod-update.sh — safe production update for the Cakra/Oak ERPNext Docker stack.
#
# Stack reality this script is written for (do not "simplify" away):
#   - TWO compose files: docker-compose.prod.yml + docker-compose.override.prod.yml
#     (the override adds per-domain bundle bind-mounts + ensure-bundles boot wrapper).
#   - Project name: erp_oak.
#   - MULTIPLE sites, each with a DIFFERENT app set:
#       app.cakraindo.com : ... erp erpnext_custom assistant crm_cakra
#       app.oakdepo.com   : ... container_depot crm erp_cmi cmi_agents erpnext_custom
#     => a single global BUILD_APPS is WRONG. We auto-derive the buildable app set
#        per-site from `bench list-apps`, so it never drifts when apps are added/removed.
#   - nginx mounts ONLY sites/ (not apps/). Assets MUST be materialized (real files,
#     not symlinks-into-apps) or every css/js/icon/image 404s. We force MATERIALIZE_ASSETS=1.
#   - Restart ORDER matters: backend/workers first, nginx LAST — restarting backend gives
#     it a new container IP; nginx caches the old upstream IP => 502 until nginx restarts too.
#
# Default flow (per site): migrate -> build assets (auto app set) -> materialize ->
#   clear caches -> restart runtime+nginx -> verify health/routes/assets.
set -euo pipefail

cd "$(dirname "$0")/.."

PROJECT_NAME="${COMPOSE_PROJECT_NAME:-erp_oak}"
COMPOSE_PROD="${COMPOSE_PROD:-docker-compose.prod.yml}"
COMPOSE_OVERRIDE="${COMPOSE_OVERRIDE:-docker-compose.override.prod.yml}"
# space-separated list of sites to update; default = both known prod sites.
SITES="${SITES:-app.cakraindo.com app.oakdepo.com}"
# apps that are never frontend-buildable / should be skipped during bench build.
SKIP_BUILD_APPS="${SKIP_BUILD_APPS:-}"
RESTART_SERVICES="${RESTART_SERVICES:-backend websocket queue-short queue-default queue-long scheduler nginx}"
# host:port the docker nginx is published on (see override) for health/route checks.
NGINX_HOSTPORT="${NGINX_HOSTPORT:-127.0.0.1:8088}"

DO_GIT_PULL="${DO_GIT_PULL:-0}"
DO_BUILD="${DO_BUILD:-0}"
NO_CACHE="${NO_CACHE:-0}"
DO_BACKUP="${DO_BACKUP:-0}"
PULL_BUNDLES="${PULL_BUNDLES:-0}"
# host dir holding the per-domain bundle git checkout(s) bind-mounted into apps/.
BUNDLE_DIR="${BUNDLE_DIR:-/home/apps/bundles/erp_cakra}"

log()  { printf '\n[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
run()  { log "+ $*"; "$@"; }
dc()   { docker compose -p "$PROJECT_NAME" -f "$COMPOSE_PROD" -f "$COMPOSE_OVERRIDE" "$@"; }

usage() {
  cat <<EOF
Usage: scripts/prod-update.sh [options]

Safe multi-site production update (2-file compose, per-site auto app build, asset materialize).

Options:
  --pull            git pull this repo (--ff-only) before update
  --pull-bundles    git pull the bundle checkout at \$BUNDLE_DIR before update
  --build           docker compose build backend before update
  --no-cache        with --build, build without Docker cache
  --backup          bench backup --with-files each site before update
  --sites "a b"     override site list (default: $SITES)
  --help            show this help

Env overrides: COMPOSE_PROJECT_NAME, COMPOSE_PROD, COMPOSE_OVERRIDE, SITES,
               SKIP_BUILD_APPS, RESTART_SERVICES, NGINX_HOSTPORT, BUNDLE_DIR.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pull) DO_GIT_PULL=1 ;;
    --pull-bundles) PULL_BUNDLES=1 ;;
    --build) DO_BUILD=1 ;;
    --no-cache) NO_CACHE=1 ;;
    --backup) DO_BACKUP=1 ;;
    --sites) shift; SITES="${1:?--sites needs a value}" ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
  shift
done

[[ -f "$COMPOSE_PROD" ]] || { echo "Missing $COMPOSE_PROD (run from repo root)" >&2; exit 1; }
[[ -f "$COMPOSE_OVERRIDE" ]] || { echo "Missing $COMPOSE_OVERRIDE" >&2; exit 1; }

log "Preflight"
run dc ps

if [[ "$DO_GIT_PULL" == "1" ]]; then
  run git pull --ff-only
fi

if [[ "$PULL_BUNDLES" == "1" ]]; then
  if [[ -d "$BUNDLE_DIR/.git" ]]; then
    run git -C "$BUNDLE_DIR" pull --ff-only
  else
    echo "WARN: $BUNDLE_DIR is not a git checkout — skipping bundle pull" >&2
  fi
fi

if [[ "$DO_BUILD" == "1" ]]; then
  if [[ "$NO_CACHE" == "1" ]]; then
    run dc build --no-cache backend
  else
    run dc build backend
  fi
  run dc up -d
fi

# Update each site with its OWN derived app set.
for SITE in $SITES; do
  log "===== Updating site: $SITE ====="
  dc exec -T \
    -e SITE_NAME="$SITE" \
    -e SKIP_BUILD_APPS="$SKIP_BUILD_APPS" \
    -e MATERIALIZE_ASSETS=1 \
    backend bash -lc '
set -euo pipefail
cd /home/frappe/frappe-bench

# Derive buildable apps from what is actually installed on THIS site.
APPS="$(bench --site "$SITE_NAME" list-apps 2>/dev/null | awk "{print \$1}" | grep -vE "^\s*$" | tr "\n" "," | sed "s/,$//")"
echo "[update] site=$SITE_NAME derived BUILD_APPS=$APPS"

echo "[update] migrate"
bench --site "$SITE_NAME" migrate

# build-assets.sh consumes BUILD_APPS/SKIP_BUILD_APPS/MATERIALIZE_ASSETS from env.
export BUILD_APPS="$APPS"
echo "[update] build + materialize assets"
/usr/local/bin/build-assets.sh

echo "[update] clear caches"
bench --site "$SITE_NAME" clear-cache
bench --site "$SITE_NAME" clear-website-cache
'
done

log "Restart runtime services + nginx (nginx LAST to avoid stale-upstream 502)"
run dc restart $RESTART_SERVICES

log "Wait for backend health"
for i in $(seq 1 30); do
  code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 8 -H "Host: ${SITES%% *}" "http://$NGINX_HOSTPORT/api/method/ping" || true)"
  if [[ "$code" == "200" ]]; then echo "ping: 200"; break; fi
  echo "ping: $code (retry $i/30)"; sleep 2
  [[ "$i" == "30" ]] && { echo "Backend health failed" >&2; exit 1; }
done

log "Verify per-site asset serving (login page + a shared icon)"
for SITE in $SITES; do
  for path in /login /assets/frappe/icons/lucide/icons.svg; do
    code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 12 -H "Host: $SITE" "http://$NGINX_HOSTPORT$path" || true)"
    printf '%-25s %-45s %s\n' "$SITE" "$path" "$code"
  done
done

log "Done. Browser may need Ctrl+Shift+R (hashed bundle names change on rebuild)."
