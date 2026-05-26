FROM frappe/bench:latest

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

USER frappe

ARG FRAPPE_REPO=https://github.com/cakra-erpnext-apps/frappe
ARG FRAPPE_BRANCH=version-16

WORKDIR /home/frappe

COPY --chown=frappe:frappe apps.json /tmp/apps.json

RUN bench init frappe-bench \
    --frappe-path ${FRAPPE_REPO} \
    --frappe-branch ${FRAPPE_BRANCH} \
    --skip-redis-config-generation \
    --skip-assets

WORKDIR /home/frappe/frappe-bench

RUN python3 - <<'PY'
import json
import subprocess
import sys

with open("/tmp/apps.json") as f:
    apps = json.load(f)

for app in apps:
    name = app["name"]
    url = app["url"]
    branch = app["branch"]

    print("=" * 80, flush=True)
    print(f"Installing app source: {name}", flush=True)
    print(f"URL    : {url}", flush=True)
    print(f"Branch : {branch}", flush=True)
    print("=" * 80, flush=True)

    try:
        subprocess.check_call([
            "bench",
            "get-app",
            "--skip-assets",
            "--branch",
            branch,
            url
        ])
    except subprocess.CalledProcessError as e:
        print("=" * 80, flush=True)
        print(f"FAILED installing app: {name}", flush=True)
        print(f"URL       : {url}", flush=True)
        print(f"Branch    : {branch}", flush=True)
        print(f"Exit code : {e.returncode}", flush=True)
        print("=" * 80, flush=True)
        sys.exit(e.returncode)
PY

COPY --chown=frappe:frappe scripts/init-site.sh /usr/local/bin/init-site.sh
COPY --chown=frappe:frappe scripts/build-assets.sh /usr/local/bin/build-assets.sh

USER root
RUN chmod +x /usr/local/bin/init-site.sh /usr/local/bin/build-assets.sh
USER frappe

WORKDIR /home/frappe/frappe-bench