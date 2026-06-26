#!/usr/bin/env bash
# ensure-bundles.sh — boot wrapper for per-domain custom app bundles (bind-mount model)
# Runs on every container start BEFORE the real service command.
# For each bind-mounted bundle sub-app: `pip install -e --no-deps` + register in sites/apps.txt.
# Idempotent + safe on recreate. Then exec the original service command ("$@").
#
# Bundle apps are bind-mounted (see docker-compose.override.prod.yml) into:
#   /home/frappe/frappe-bench/apps/<app>
# Controlled by env BUNDLE_APPS (space-separated). Install to a SITE is done separately
# (bench --site <domain> install-app <app>) — this wrapper only makes the code importable.
set -euo pipefail

BENCH=/home/frappe/frappe-bench
cd "$BENCH"

# space-separated list of bundle app dir names present under apps/
BUNDLE_APPS="${BUNDLE_APPS:-erp erpnext_custom assistant crm_cakra}"
# extra python deps required by bundle apps (not in baked image). Reinstalled on boot
# because container site-packages are ephemeral on recreate. Needs egress.
BUNDLE_PYDEPS="${BUNDLE_PYDEPS:-pypdfium2 twilio==8.5.0}"
APPS_TXT="$BENCH/sites/apps.txt"

# Materialize assets so nginx (which mounts ONLY sites/, NOT apps/) can serve them.
# Default-on. Set MATERIALIZE_ASSETS=0 in dev (where the symlink + asset watcher is wanted).
MATERIALIZE_ASSETS="${MATERIALIZE_ASSETS:-1}"

log() { echo "[ensure-bundles] $*"; }

# ensure extra python deps (idempotent; pip is fast no-op if already satisfied)
if [ -n "$BUNDLE_PYDEPS" ]; then
  log "ensure pydeps: $BUNDLE_PYDEPS"
  ./env/bin/pip install -q $BUNDLE_PYDEPS || log "WARN pydeps install failed (will retry next boot)"
fi

for app in $BUNDLE_APPS; do
  dir="$BENCH/apps/$app"
  if [ ! -d "$dir" ]; then
    log "SKIP $app — not mounted at $dir"
    continue
  fi
  # editable install (no deps to avoid egress for transitive pkgs; deps handled at build/install-app)
  if ! ./env/bin/pip show "$app" >/dev/null 2>&1; then
    log "pip install -e $app"
    ./env/bin/pip install -e "$dir" --no-deps -q || log "WARN pip install -e $app failed (will retry next boot)"
  else
    log "$app already pip-installed"
  fi
  # register in apps.txt (idempotent)
  if [ -f "$APPS_TXT" ] && ! grep -qxF "$app" "$APPS_TXT"; then
    log "append $app -> apps.txt"
    echo "$app" >> "$APPS_TXT"
  fi
done

# --- Materialize symlinked assets into real files (self-heal for nginx) ---------------
# Frappe's `bench build` (and bench setup) leaves sites/assets/<app> as a SYMLINK into
# apps/<app>/<app>/public. The nginx container mounts only the sites/ volume and has NO
# apps/ dir, so it cannot follow those symlinks -> every asset 404s (css/js/icons/images).
# We replace each symlink with a real copy of its target. Idempotent: only acts when the
# entry is still a symlink (a real dir from a prior materialize or `bench build --hard-link`
# is left untouched, so this is a fast no-op on subsequent boots).
if [ "$MATERIALIZE_ASSETS" = "1" ] && [ -d "$BENCH/sites/assets" ]; then
  materialized=0
  for link in "$BENCH"/sites/assets/*; do
    [ -L "$link" ] || continue            # only symlinks
    target="$(readlink -f "$link" || true)"
    [ -n "$target" ] && [ -d "$target" ] || continue
    name="$(basename "$link")"
    rm -f "$link"
    cp -r "$target" "$link"
    materialized=$((materialized + 1))
    log "materialized assets: $name"
  done
  if [ "$materialized" -gt 0 ]; then
    log "materialized $materialized asset symlink(s) -> real dirs (nginx-servable)"
  else
    log "assets already materialized (no symlinks) — skip"
  fi
fi

log "ready — exec: $*"
exec "$@"
