#!/usr/bin/env bash
set -euo pipefail

# version-check.sh [dev|prod]
#
# Bandingkan commit app yang BENAR-BENAR jalan di dalam container (Layer C)
# dengan commit terbaru di GitHub fork (Layer B), lalu print SYNCED / STALE
# per app. Folder app lokal di host (Layer D) sengaja TIDAK dipakai sebagai
# patokan — itu bukan yang dijalankan container.
#
# Exit code: 0 = semua synced, 2 = ada yang stale, 1 = error setup.

cd "$(dirname "$0")/.."

ENV="${1:-dev}"

case "$ENV" in
  dev)  COMPOSE_FILE="docker-compose.dev.yml";  SERVICE="frappe"  ;;
  prod) COMPOSE_FILE="docker-compose.prod.yml"; SERVICE="backend" ;;
  *)    echo "Usage: $0 [dev|prod]" >&2; exit 1 ;;
esac

# frappe tidak ada di apps.json (di-install lewat bench init pakai env ini).
if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
fi
export FRAPPE_REPO="${FRAPPE_REPO:-https://github.com/cakra-erpnext-apps/frappe}"
export FRAPPE_BRANCH="${FRAPPE_BRANCH:-version-16}"

# --- Pastikan container target running ---
if ! docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE" true 2>/dev/null; then
  echo "ERROR: service '$SERVICE' ($COMPOSE_FILE) tidak running." >&2
  echo "Jalankan dulu: docker compose -f $COMPOSE_FILE up -d" >&2
  exit 1
fi

# --- Layer C: commit tiap app yang baked di dalam container ---
declare -A RUNNING
while IFS=$'\t' read -r app hash; do
  [ -n "$app" ] && RUNNING["$app"]="$hash"
done < <(docker compose -f "$COMPOSE_FILE" exec -T "$SERVICE" bash -c '
  cd /home/frappe/frappe-bench/apps 2>/dev/null || exit 0
  for d in */; do
    a="${d%/}"
    h="$(git -C "$a" rev-parse HEAD 2>/dev/null || echo "-")"
    printf "%s\t%s\n" "$a" "$h"
  done')

# --- App bind-mount (Layer D langsung jadi Layer C) ---
# STALE di app mount = folder host ketinggalan, fix-nya `git pull` + migrate,
# BUKAN rebuild image.
declare -A MOUNTED
while read -r m; do
  [ -n "$m" ] && MOUNTED["$m"]=1
done < <(grep -oE '\./[A-Za-z0-9_.-]+:/home/frappe/frappe-bench/apps/[A-Za-z0-9_.-]+' \
           "$COMPOSE_FILE" 2>/dev/null | sed -E 's#.*/apps/##' | sort -u)

# --- Daftar app yang DIHARAPKAN + url + branch (Layer B) ---
# frappe dari env, sisanya dari apps.json.
APPSPEC="$(python3 - <<'PY'
import json, os
print("frappe\t%s\t%s" % (os.environ["FRAPPE_REPO"], os.environ["FRAPPE_BRANCH"]))
try:
    with open("apps.json") as f:
        for a in json.load(f):
            print("%s\t%s\t%s" % (a["name"], a["url"], a["branch"]))
except FileNotFoundError:
    pass
PY
)"

printf "%-16s %-8s %-9s %-9s %s\n" "APP" "KIND" "RUNNING" "GITHUB" "STATUS"
printf '%s\n' "----------------------------------------------------------------------"

baked_stale=0
mount_stale=0
declare -a MOUNT_STALE_APPS=()
while IFS=$'\t' read -r app url branch; do
  [ -z "$app" ] && continue

  remote="$(git ls-remote "$url" "refs/heads/$branch" 2>/dev/null | awk 'NR==1{print $1}')" || true
  local="${RUNNING[$app]:-}"
  if [ -n "${MOUNTED[$app]:-}" ]; then kind="mount"; else kind="baked"; fi

  if [ -z "$remote" ]; then
    status="?? remote tak terbaca (offline / branch salah?)"
  elif [ -z "$local" ] || [ "$local" = "-" ]; then
    status="MISSING (tidak ada / bukan git di container)"
    baked_stale=1
  elif [ "$remote" = "$local" ]; then
    status="SYNCED"
  elif [ "$kind" = "mount" ]; then
    status="STALE -> git pull ./$app"
    mount_stale=1
    MOUNT_STALE_APPS+=("$app")
  else
    status="STALE -> rebuild --no-cache"
    baked_stale=1
  fi

  printf "%-16s %-8s %-9s %-9s %s\n" "$app" "$kind" "${local:0:7}" "${remote:0:7}" "$status"
done <<< "$APPSPEC"

echo
if [ "$baked_stale" -eq 1 ]; then
  echo "App BAKED stale/missing -> rebuild image + recreate:"
  echo "  docker compose -f $COMPOSE_FILE build --no-cache && \\"
  echo "  docker compose -f $COMPOSE_FILE up -d --force-recreate"
fi
if [ "$mount_stale" -eq 1 ]; then
  echo "App MOUNT stale -> tarik folder host (TANPA rebuild):"
  for a in "${MOUNT_STALE_APPS[@]}"; do
    echo "  git -C $a pull"
  done
  echo "  scripts/migrate.sh   # kalau ada perubahan DocType/fixture/patch"
fi

if [ "$baked_stale" -eq 1 ] || [ "$mount_stale" -eq 1 ]; then
  exit 2
fi

echo "Semua app SYNCED dengan GitHub. Bench kamu benar-benar terbaru."
