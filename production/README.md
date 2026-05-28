# Production deployment notes: Oakdepo / Frappe Docker compatible image

This repo has two Docker approaches:

- Root `Dockerfile`: bench/dev or staging style image. Good for local/staging, but not compatible with current Oakdepo production compose because it does not provide Frappe Docker frontend/runtime entrypoints.
- `production/Containerfile.layered`: Frappe Docker compatible layered image. Use this for Oakdepo production.

## Why production needs layered image

Current Oakdepo production compose has these services:

- `backend`
- `frontend`
- `websocket`
- `scheduler`
- `queue-short`
- `queue-long`
- `mariadb`
- `redis-cache`
- `redis-queue`

The `frontend` service expects Frappe Docker runtime scripts:

- `/usr/local/bin/entrypoint.sh`
- `/usr/local/bin/nginx-entrypoint.sh`

The root `Dockerfile` based on `frappe/bench:latest` does not include those scripts. Do not switch Oakdepo prod to that image directly.

## Build production image

Use helper script:

```bash
./scripts/build-oakdepo-frappe-docker-image.sh
```

Default output image:

```text
erpnext-custom:cakra-frappe-docker-YYYYMMDD
```

The script expects:

- `BASE=/home/apps/oakdepo`
- `APPS_JSON=$BASE/gitops/apps.json`
- `FRAPPE_DOCKER=$BASE/frappe_docker`

Override via env vars if needed.

## Required apps source

Use `production/apps.oakdepo.json` as app list. It pulls apps from `https://github.com/cakra-erpnext-apps/*`.

Important: `erpnext_custom` is intentionally minimal/as-is. Old Oakdepo modules (`Depo`, `Payroll Custom`) must be removed from existing site before migrating to this image.

## Existing Oakdepo migration runbook

1. Backup site and files:

```bash
docker exec oakdepo-prod-backend-1 bash -lc 'cd /home/frappe/frappe-bench && bench --site app.oakdepo.com backup --with-files'
```

2. Remove obsolete old module DocTypes if migrating from old Oakdepo custom app:

```text
Container Stock
Depo Location
Gate In
Gate Out
Gaji Entry
Module Def: Depo
Module Def: Payroll Custom
```

Prefer Frappe API deletion while old image is still running, after backup.

3. Build Frappe Docker compatible Cakra image.

4. Change image refs in Oakdepo compose only:

```text
erpnext-custom:16 -> erpnext-custom:cakra-frappe-docker-YYYYMMDD
```

5. Recreate app containers with explicit project name:

```bash
cd /home/apps/oakdepo/gitops
COMPOSE_PROJECT_NAME=oakdepo-prod docker compose -p oakdepo-prod -f oakdepo-prod.yaml up -d --no-deps --force-recreate backend websocket scheduler queue-short queue-long frontend
```

Do not omit `-p oakdepo-prod`; otherwise Docker Compose may create a separate `gitops-*` stack and collide on port `127.0.0.1:8088`.

6. Migrate and clear cache:

```bash
docker exec oakdepo-prod-backend-1 bash -lc 'cd /home/frappe/frappe-bench && bench --site app.oakdepo.com migrate && bench --site app.oakdepo.com clear-cache && bench --site app.oakdepo.com clear-website-cache'
```

7. Verify:

```bash
curl -kIs --max-time 15 https://app.oakdepo.com/login | head -12
docker ps -a --format '{{.Names}}\t{{.Status}}\t{{.Image}}\t{{.Ports}}' | grep '^oakdepo-prod-'
docker logs --tail 100 oakdepo-prod-backend-1 | grep -Ei 'error|traceback|exception|failed' || true
```

## Rollback

If migration fails before schema changes, switch compose image refs back to:

```text
erpnext-custom:16
```

Then recreate app containers with `-p oakdepo-prod`.

If schema changes or old module deletion must be reverted, restore database from pre-migration backup.

## Current successful migration reference

On 2026-05-28 Oakdepo production migrated successfully to:

```text
erpnext-custom:cakra-frappe-docker-20260528
```

Validation:

- `/login` returned `200 OK`
- `/desk` redirected guest to login
- `bench migrate` succeeded
- old DocTypes were removed before switching to minimal `erpnext_custom`
