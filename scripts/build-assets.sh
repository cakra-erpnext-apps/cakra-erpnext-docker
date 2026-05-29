#!/usr/bin/env bash
set -euo pipefail

cd /home/frappe/frappe-bench

BUILD_APPS="${BUILD_APPS:-frappe,erpnext,hrms}"
SKIP_BUILD_APPS="${SKIP_BUILD_APPS:-erpnext_custom}"
ASSET_STRICT="${ASSET_STRICT:-0}"

echo "=================================================="
echo "Preparing assets"
echo "Build apps      : ${BUILD_APPS}"
echo "Skip build apps : ${SKIP_BUILD_APPS}"
echo "Strict mode     : ${ASSET_STRICT}"
echo "=================================================="

echo "Installing node dependencies for apps that have package.json..."

for app_dir in apps/*; do
  if [ ! -d "$app_dir" ]; then
    continue
  fi

  app="$(basename "$app_dir")"

  if [ -f "$app_dir/package.json" ]; then
    echo "Installing node dependencies for app: ${app}"

    cd "$app_dir"

    if [ -f "yarn.lock" ]; then
      yarn install --check-files || yarn install
    else
      yarn install --check-files || yarn install
    fi

    cd /home/frappe/frappe-bench
  fi
done

echo "Building selected app assets..."

IFS=',' read -ra APPS <<< "$BUILD_APPS"

for app in "${APPS[@]}"; do
  app="$(echo "$app" | xargs)"

  if [ -z "$app" ]; then
    continue
  fi

  if [ ! -d "apps/${app}" ]; then
    echo "Skipping missing app: ${app}"
    continue
  fi

  if echo ",${SKIP_BUILD_APPS}," | grep -q ",${app},"; then
    echo "Skipping asset build for app: ${app}"
    continue
  fi

  echo "Building assets for app: ${app}"

  if bench build --app "$app"; then
    echo "Asset build finished for app: ${app}"
  else
    echo "WARNING: asset build failed for app: ${app}"

    if [ "$ASSET_STRICT" = "1" ]; then
      echo "Strict mode enabled. Exiting."
      exit 1
    fi

    echo "Continuing because ASSET_STRICT=0"
  fi
done

MATERIALIZE_ASSETS="${MATERIALIZE_ASSETS:-0}"

if [ "$MATERIALIZE_ASSETS" = "1" ]; then
  echo "Materializing sites/assets/<app> from apps/<app>/<app>/public..."

  cd /home/frappe/frappe-bench/sites/assets

  for app_dir in /home/frappe/frappe-bench/apps/*/; do
    app="$(basename "$app_dir")"
    src="${app_dir}${app}/public"

    if [ ! -d "$src" ]; then
      continue
    fi

    if [ -L "$app" ] || [ -d "$app" ]; then
      rm -rf "$app"
    fi

    cp -r "$src" "$app"
  done

  cd /home/frappe/frappe-bench
else
  echo "Skipping asset materialization (MATERIALIZE_ASSETS != 1)"
  echo "Note: required for nginx:alpine in prod, breaks watcher in dev."
fi

echo "Clearing Frappe caches..."

bench clear-cache || true
bench clear-website-cache || true

echo "Asset preparation finished."