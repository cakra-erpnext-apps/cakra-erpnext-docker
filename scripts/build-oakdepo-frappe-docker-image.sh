#!/usr/bin/env bash
set -euo pipefail

BASE=${BASE:-/home/apps/oakdepo}
APPS_JSON=${APPS_JSON:-$BASE/gitops/apps.json}
FRAPPE_DOCKER=${FRAPPE_DOCKER:-$BASE/frappe_docker}
IMAGE=${IMAGE:-erpnext-custom}
TAG=${TAG:-cakra-frappe-docker-$(date +%Y%m%d)}
LOG=${LOG:-$BASE/logs/build-image-$(date +%Y%m%d-%H%M%S).log}

APPS_JSON_HASH=$(python3 - "$APPS_JSON" <<'PYHASH'
import hashlib, sys
print(hashlib.sha256(open(sys.argv[1], "rb").read()).hexdigest())
PYHASH
)

echo "[INFO] apps_json=$APPS_JSON"
echo "[INFO] apps_json_hash=$APPS_JSON_HASH"
echo "[INFO] image=$IMAGE:$TAG"

cd "$FRAPPE_DOCKER"
docker build \
  --network=host \
  --progress=plain \
  --build-arg=FRAPPE_PATH=https://github.com/cakra-erpnext-apps/frappe \
  --build-arg=FRAPPE_BRANCH=version-16 \
  --build-arg=APPS_JSON_HASH="$APPS_JSON_HASH" \
  --secret=id=apps_json,src="$APPS_JSON" \
  --tag="$IMAGE:$TAG" \
  --file=images/layered/Containerfile . 2>&1 | tee "$LOG"

echo "[INFO] log=$LOG"
