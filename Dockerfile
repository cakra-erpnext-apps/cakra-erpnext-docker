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

COPY --chown=frappe:frappe scripts/install-apps.py /tmp/install-apps.py
# yarn v1 + optionalDependencies multi-OS (turbo di raven) → `yarn install
# --check-files` ENOENT di .yarn-metadata.json untuk binary OS lain
# (mis. turbo-darwin-64 di build Linux). ignore-optional skip semua binary
# platform supaya get-app lolos. Di-scope ke RUN ini saja: runtime
# build-assets.sh sudah punya fallback `yarn install --check-files || yarn install`
# yang meng-install turbo-linux-64 normal. .yarnrc lama (kalau ada) di-restore.
RUN cp /home/frappe/.yarnrc /home/frappe/.yarnrc.bak 2>/dev/null || true \
    && printf -- '--install.ignore-optional true\n' >> /home/frappe/.yarnrc \
    && python3 /tmp/install-apps.py \
    && { mv /home/frappe/.yarnrc.bak /home/frappe/.yarnrc 2>/dev/null || rm -f /home/frappe/.yarnrc; }

COPY --chown=frappe:frappe scripts/init-site.sh /usr/local/bin/init-site.sh
COPY --chown=frappe:frappe scripts/build-assets.sh /usr/local/bin/build-assets.sh

USER root
RUN chmod +x /usr/local/bin/init-site.sh /usr/local/bin/build-assets.sh
USER frappe

WORKDIR /home/frappe/frappe-bench