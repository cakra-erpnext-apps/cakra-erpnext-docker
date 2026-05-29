#!/usr/bin/env bash
# Daily backup script for production.
# Runs `bench backup` inside the backend container, then copies the artifacts
# out of the named volume to ./backups/ on host.
#
# Add to host crontab:
#   0 2 * * * cd /opt/oak_app && ./scripts/backup.sh >> /var/log/oak-backup.log 2>&1
set -euo pipefail

cd "$(dirname "$0")/.."

COMPOSE="docker compose -f docker-compose.prod.yml"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-14}"

# shellcheck disable=SC1091
set -a; source .env; set +a

mkdir -p ./backups

echo "=== $(date -Iseconds) backup start (site=$SITE_NAME) ==="

# 1. Trigger bench backup inside container — writes to the bench-sites volume.
$COMPOSE exec -T backend \
  bash -c "bench --site '$SITE_NAME' backup --with-files --compress"

# 2. Copy site_config.json into the backup folder. Contains encryption_key —
#    without it, encrypted Password fields can't be decoded on restore.
$COMPOSE exec -T backend \
  bash -c "cp -f sites/'$SITE_NAME'/site_config.json sites/'$SITE_NAME'/private/backups/site_config.json"

# 3. Stream the backup folder out of the volume to the host's ./backups/.
CONTAINER_ID="$($COMPOSE ps -q backend)"
if [ -z "$CONTAINER_ID" ]; then
  echo "ERROR: backend container is not running."
  exit 1
fi
docker cp "$CONTAINER_ID:/home/frappe/frappe-bench/sites/$SITE_NAME/private/backups/." ./backups/

# 4. Prune host-side backups older than retention window.
find ./backups -type f -mtime "+${RETENTION_DAYS}" \
  \( -name '*.sql.gz' -o -name '*-files.tar' -o -name '*-private-files.tar' \) \
  -print -delete || true

echo "=== $(date -Iseconds) backup done ==="

# OPTIONAL: upload to off-host storage. Uncomment and configure one of these:
#
# # rclone (any cloud, configure ~/.config/rclone/rclone.conf first):
# rclone copy ./backups remote:oak-backups/$(date +%F) --include "*.gz" --include "*.tar" --include "site_config.json"
#
# # aws s3:
# aws s3 sync ./backups s3://your-bucket/oak-backups/$(date +%F)/ --exclude "*" --include "*.gz" --include "*.tar" --include "site_config.json"
