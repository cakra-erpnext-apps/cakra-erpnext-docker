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

# Cypress/Puppeteer/Playwright download binary E2E dari CDN pihak ketiga saat
# postinstall yarn. Build container tidak punya egress ke CDN itu (hanya clone
# GitHub yang jalan) dan image produksi tidak pernah menjalankan E2E, jadi skip
# via env var resmi tiap tool — BUKAN flag global yarn. Dengan begitu
# optionalDependencies native per-platform (turbo di raven, @rollup/rollup-
# linux-x64-gnu di app Vite) tetap di-resolve normal di dalam container Linux.
ENV CYPRESS_INSTALL_BINARY=0 \
    PUPPETEER_SKIP_DOWNLOAD=1 \
    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1

RUN python3 /tmp/install-apps.py

COPY --chown=frappe:frappe scripts/init-site.sh /usr/local/bin/init-site.sh
COPY --chown=frappe:frappe scripts/build-assets.sh /usr/local/bin/build-assets.sh

USER root
RUN chmod +x /usr/local/bin/init-site.sh /usr/local/bin/build-assets.sh
USER frappe

WORKDIR /home/frappe/frappe-bench