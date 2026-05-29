#!/usr/bin/env bash
set -euo pipefail

cd /home/frappe/frappe-bench

SITE_NAME="${SITE_NAME:-erp.localhost}"
DB_HOST="${DB_HOST:-mariadb}"
DB_PORT="${DB_PORT:-3306}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-123}"
ADMIN_PASSWORD="${ADMIN_PASSWORD:-admin}"
DEVELOPER_MODE="${DEVELOPER_MODE:-0}"

REDIS_CACHE="${REDIS_CACHE:-redis://redis-cache:6379}"
REDIS_QUEUE="${REDIS_QUEUE:-redis://redis-queue:6379}"
REDIS_SOCKETIO="${REDIS_SOCKETIO:-redis://redis-socketio:6379}"
SOCKETIO_PORT="${SOCKETIO_PORT:-9000}"

INSTALL_APPS="${INSTALL_APPS:-erpnext}"

echo "=================================================="
echo "Initializing Frappe site"
echo "Site          : ${SITE_NAME}"
echo "Database host : ${DB_HOST}:${DB_PORT}"
echo "Install apps  : ${INSTALL_APPS}"
echo "=================================================="

wait_for_database() {
  echo "Waiting for database at ${DB_HOST}:${DB_PORT}..."

  if command -v nc >/dev/null 2>&1; then
    until nc -z "$DB_HOST" "$DB_PORT"; do
      sleep 2
    done
  else
    until python3 - <<PY
import socket
import sys

host = "${DB_HOST}"
port = int("${DB_PORT}")

try:
    sock = socket.create_connection((host, port), timeout=2)
    sock.close()
except Exception:
    sys.exit(1)
PY
    do
      sleep 2
    done
  fi

  echo "Database is reachable."
}

regenerate_apps_txt() {
  echo "Regenerating sites/apps.txt..."

  mkdir -p sites

  {
    echo "frappe"

    for dir in apps/*; do
      if [ -d "$dir" ]; then
        app="$(basename "$dir")"

        if [ "$app" != "frappe" ]; then
          echo "$app"
        fi
      fi
    done
  } > sites/apps.txt

  echo "Current sites/apps.txt:"
  cat sites/apps.txt
}

configure_common_site_config() {
  echo "Setting common site config..."

  mkdir -p sites

  bench set-config -g db_host "$DB_HOST"
  bench set-config -g db_port "$DB_PORT"
  bench set-config -g redis_cache "$REDIS_CACHE"
  bench set-config -g redis_queue "$REDIS_QUEUE"
  bench set-config -g redis_socketio "$REDIS_SOCKETIO"
  bench set-config -g socketio_port "$SOCKETIO_PORT"
  bench set-config -gp developer_mode "$DEVELOPER_MODE"

  echo "Current common_site_config.json:"
  cat sites/common_site_config.json || true
}

create_site_if_needed() {
  if [ ! -d "sites/${SITE_NAME}" ]; then
    echo "Creating site: ${SITE_NAME}"

    bench new-site "$SITE_NAME" \
      --mariadb-root-password "$MYSQL_ROOT_PASSWORD" \
      --admin-password "$ADMIN_PASSWORD" \
      --db-host "$DB_HOST" \
      --db-port "$DB_PORT" \
      --no-mariadb-socket

    bench use "$SITE_NAME"
  else
    echo "Site already exists: ${SITE_NAME}"
    bench use "$SITE_NAME"
  fi
}

is_app_installed() {
  local app="$1"

  bench --site "$SITE_NAME" list-apps | awk '{print $1}' | grep -qx "$app"
}

install_apps() {
  echo "Installing apps: ${INSTALL_APPS}"

  IFS=',' read -ra APPS <<< "$INSTALL_APPS"

  for app in "${APPS[@]}"; do
    app="$(echo "$app" | xargs)"

    if [ -z "$app" ]; then
      continue
    fi

    if [ ! -d "apps/${app}" ]; then
      echo "WARNING: app source not found: apps/${app}"
      echo "Skipping app: ${app}"
      continue
    fi

    if ! grep -qx "$app" sites/apps.txt; then
      echo "Adding ${app} to sites/apps.txt"
      echo "$app" >> sites/apps.txt
    fi

    if is_app_installed "$app"; then
      echo "App already installed: ${app}"
    else
      echo "Installing app: ${app}"
      bench --site "$SITE_NAME" install-app "$app"
    fi
  done
}

run_migrate() {
  echo "Running migrate..."
  bench --site "$SITE_NAME" migrate
}

wait_for_database
regenerate_apps_txt
configure_common_site_config
create_site_if_needed
regenerate_apps_txt
install_apps
run_migrate

echo "Site initialization finished."

exec "$@"