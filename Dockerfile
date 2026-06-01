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
RUN python3 /tmp/install-apps.py

COPY --chown=frappe:frappe scripts/init-site.sh /usr/local/bin/init-site.sh
COPY --chown=frappe:frappe scripts/build-assets.sh /usr/local/bin/build-assets.sh

USER root
RUN chmod +x /usr/local/bin/init-site.sh /usr/local/bin/build-assets.sh
USER frappe

WORKDIR /home/frappe/frappe-bench