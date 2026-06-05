# Cakra ERPNext Docker

Docker setup untuk menjalankan Frappe/ERPNext v16 dari fork repository `cakra-erpnext-apps`.

Setup ini dibuat untuk dua kebutuhan:

- **Local development** menggunakan `bench start`
- **Production-like / staging** dengan service terpisah: backend, websocket, workers, scheduler, MariaDB, dan Redis

> Catatan: setup production di repo ini masih membutuhkan reverse proxy seperti Nginx, Caddy, atau Traefik jika ingin dipakai untuk domain publik + SSL.

---

## Repository Structure

Repo ini sebaiknya hanya berisi file Docker/deployment, bukan source app Frappe.

```text
cakra-erpnext-docker/
├── Dockerfile
├── apps.json
├── docker-compose.dev.yml
├── docker-compose.prod.yml
├── .env.example
├── README.md
└── scripts/
    ├── init-site.sh
    └── build-assets.sh
```

Folder app seperti ini **tidak perlu dimasukkan ke repo Docker**:

```text
frappe/
erpnext/
hrms/
crm/
helpdesk/
raven/
gameplan/
telephony/
erpnext_custom/
```

Semua app diambil dari GitHub melalui `apps.json`.

---

## Apps yang Digunakan

Semua app diasumsikan berada di organization:

```text
https://github.com/cakra-erpnext-apps
```

Branch yang disarankan:

```text
frappe          version-16
erpnext         version-16
hrms            version-16
erpnext_custom  main
crm             main
helpdesk        main
raven           main
gameplan        main
telephony       develop
```

---

## apps.json

`apps.json` digunakan saat Docker build untuk mengambil source app menggunakan `bench get-app --skip-assets`.

```json
[
  {
    "name": "erpnext",
    "url": "https://github.com/cakra-erpnext-apps/erpnext",
    "branch": "version-16"
  },
  {
    "name": "hrms",
    "url": "https://github.com/cakra-erpnext-apps/hrms",
    "branch": "version-16"
  },
  {
    "name": "erpnext_custom",
    "url": "https://github.com/cakra-erpnext-apps/erpnext_custom",
    "branch": "main"
  },
  {
    "name": "crm",
    "url": "https://github.com/cakra-erpnext-apps/crm",
    "branch": "main"
  },
  {
    "name": "helpdesk",
    "url": "https://github.com/cakra-erpnext-apps/helpdesk",
    "branch": "main"
  },
  {
    "name": "raven",
    "url": "https://github.com/cakra-erpnext-apps/raven",
    "branch": "main"
  },
  {
    "name": "gameplan",
    "url": "https://github.com/cakra-erpnext-apps/gameplan",
    "branch": "main"
  },
  {
    "name": "telephony",
    "url": "https://github.com/cakra-erpnext-apps/telephony",
    "branch": "develop"
  }
]
```

---

## .env

Buat file `.env` dari `.env.example`.

```env
COMPOSE_PROJECT_NAME=cakra_erpnext

SITE_NAME=erp.localhost
ADMIN_PASSWORD=admin
MYSQL_ROOT_PASSWORD=123

FRAPPE_REPO=https://github.com/cakra-erpnext-apps/frappe
FRAPPE_BRANCH=version-16

INSTALL_APPS=erpnext,hrms,erpnext_custom,crm,helpdesk,raven,gameplan,telephony

BUILD_APPS=frappe,erpnext,hrms,crm,helpdesk,raven,gameplan,telephony
SKIP_BUILD_APPS=erpnext_custom
ASSET_STRICT=0

# Hanya dipakai di docker-compose.dev.yml.
# Default 1 di dev (lihat docker-compose.dev.yml), default 0 di prod.
# Aktifkan developer_mode supaya assets.json selalu dibaca fresh dari disk
# (mencegah 404 di bundle desk/erpnext/hrms setelah migrate/test memicu rebuild).
DEVELOPER_MODE=1
```

### Perbedaan `INSTALL_APPS` dan `BUILD_APPS`

```text
INSTALL_APPS = app yang dipasang ke site Frappe
BUILD_APPS   = app yang CSS/JS assets-nya dibuild
```

`erpnext_custom` tetap bisa di-install, tetapi tidak perlu asset build jika app tersebut tidak punya frontend asset sendiri.

Jika ada app yang error saat asset build, tambahkan ke `SKIP_BUILD_APPS`.

```env
SKIP_BUILD_APPS=erpnext_custom,telephony
```

---

## Dockerfile Concept

Dockerfile hanya melakukan:

1. Install package tambahan seperti `netcat-openbsd`
2. `bench init` menggunakan fork `frappe`
3. `bench get-app --skip-assets` untuk semua app di `apps.json`
4. Copy script `init-site.sh` dan `build-assets.sh`

Dockerfile **tidak menjalankan `bench build` langsung**. Asset build dijalankan saat container start melalui `build-assets.sh`, supaya lebih fleksibel untuk development dan tidak membuat image build gagal karena satu app bermasalah.

---

## Local Development

Jalankan:

```bash
docker compose -f docker-compose.dev.yml up --build
```

Atau background:

```bash
docker compose -f docker-compose.dev.yml up -d --build
```

Buka:

```text
http://127.0.0.1:8000
```

Login default:

```text
Username: Administrator
Password: admin
```

Password mengikuti `ADMIN_PASSWORD` di `.env`.

---

## Development Services

`docker-compose.dev.yml` menjalankan service:

```text
mariadb
redis-cache
redis-queue
redis-socketio
frappe
```

Service `frappe` menjalankan:

```bash
init-site.sh build-assets.sh && bench start
```

Artinya:

1. Menunggu database siap
2. Membuat site jika belum ada
3. Install apps dari `INSTALL_APPS`
4. Migrate
5. Build assets dari `BUILD_APPS`
6. Menjalankan `bench start`

---

## Live Code Editing (Bind Mount)

App yang aktif dikembangkan di-mount langsung dari host ke dalam container, sehingga edit di VSCode langsung terlihat tanpa rebuild image.

`docker-compose.dev.yml` punya bind mount:

```yaml
volumes:
  - ./erpnext_custom:/home/frappe/frappe-bench/apps/erpnext_custom
  - ./container_depot:/home/frappe/frappe-bench/apps/container_depot
```

App lain (frappe, erpnext, hrms, crm, helpdesk, raven, gameplan, telephony) tetap baked di image, supaya container start cepat dan image tetap bisa dipakai untuk production.

### Yang otomatis reload

```text
Python (.py)         bench start auto-reload worker
JS / CSS / SCSS      bench watch rebuild bundle, refresh browser
```

### Yang butuh perintah manual

```text
DocType / fixture baru atau berubah   scripts/migrate.sh
hooks.py atau scheduled job berubah   scripts/restart.sh
```

### Permission

Container jalan sebagai user `frappe` (UID 1000). Pada WSL2 user host biasanya juga UID 1000, jadi bind mount langsung bisa tulis. Kalau muncul permission error di `__pycache__` atau `.egg-info`, cek `id -u` di host — kalau bukan 1000, alignment perlu di-fix.

### Asset build untuk app yang di-mount

`erpnext_custom` dan `container_depot` ada di `SKIP_BUILD_APPS` di `.env`. Selama belum ada JS/CSS baru, ini aman. Begitu menambah file di `<app>/public/`, hapus app tersebut dari `SKIP_BUILD_APPS` dan tambahkan ke `BUILD_APPS` supaya bundle ikut ter-build.

---

## Helper Scripts

Wrapper tipis untuk operasi dev yang paling sering dipakai. Semua skrip aman dipanggil dari direktori manapun karena `cd` ke project root sendiri.

```text
scripts/migrate.sh           bench migrate + clear-cache + clear-website-cache
scripts/restart.sh           docker compose restart frappe
scripts/shell.sh             masuk container (exec kalau running, run --rm kalau tidak)
scripts/logs.sh [service]    tail logs, default service = frappe
scripts/test.sh [app]        bench run-tests + clear-cache + clear-website-cache, default app = erpnext_custom
```

`migrate.sh` dan `test.sh` selalu menutup dengan `clear-cache` dan `clear-website-cache`. Ini belt-and-suspenders untuk shared `assets_json` cache di Redis: kalau ada yang mematikan `developer_mode` di dev, bug 404 bundle (lihat troubleshooting) tidak akan terjadi.

Contoh:

```bash
scripts/migrate.sh
scripts/test.sh container_depot
scripts/logs.sh
```

---

## Verifikasi Setup Bind Mount

Langkah pertama kali setelah bind mount diaktifkan, atau setelah clone repo di mesin baru.

### 1. Cek UID host

```bash
id -u
```

Harus `1000` supaya cocok dengan user `frappe` di container. Kalau bukan 1000, permission write di `__pycache__` / `.egg-info` akan gagal dan perlu di-fix dulu sebelum lanjut.

### 2. Reload container

Volume berubah, jadi container harus di-recreate. Database dan site tetap aman karena bukan `down -v`.

```bash
docker compose -f docker-compose.dev.yml down
docker compose -f docker-compose.dev.yml up -d
scripts/logs.sh
```

Tunggu sampai `bench start` jalan dan ada output dari `watch`, `socketio`, dan `worker`.

### 3. Verifikasi bind mount kepakai

```bash
scripts/shell.sh
ls -la apps/erpnext_custom/
exit
```

Isi folder harus sama persis dengan folder host (ada `pyproject.toml`, `erpnext_custom.egg-info`, dll.).

Test reload: edit satu file Python di host (misal tambah `print("hello")` di sebuah API endpoint), trigger endpoint tersebut, dan `print` harus muncul di `scripts/logs.sh` tanpa rebuild image.

### 4. Smoke test

Buka [http://127.0.0.1:8000](http://127.0.0.1:8000), login `Administrator` / `ADMIN_PASSWORD`. Pastikan:

```text
erpnext_custom DocTypes muncul
container_depot module muncul di Module List
```

Kalau app tidak ke-install, jalankan manual:

```bash
scripts/shell.sh
bench --site erp.localhost install-app container_depot
exit
```

### 5. Commit perubahan Docker repo

```bash
git status
git add docker-compose.dev.yml scripts/ README.md
git commit -m "Add bind mounts and helper scripts for live app dev"
```

---

## Production Deployment

Setup production di repo ini sudah include: stack lengkap (mariadb, redis x3, configurator, backend, websocket, 3 queue worker, scheduler), nginx reverse proxy, healthcheck di setiap service, log rotation, dan backup script. Yang belum: TLS cert (kamu generate sendiri pakai Let's Encrypt) dan off-site backup upload (uncomment di `scripts/backup.sh`).

### Service yang berjalan

```text
mariadb         database
redis-cache     cache
redis-queue     job queue
redis-socketio  realtime pub/sub
configurator    bootstrap site (run sekali, exit)
backend         gunicorn web server (port 8000, internal)
websocket       realtime server (port 9000, internal)
queue-short     worker untuk job pendek
queue-default   worker untuk job default
queue-long      worker untuk job panjang
scheduler       cron scheduler
nginx           internal reverse proxy (bind 127.0.0.1:8088, fronted by host proxy)
```

Docker nginx bind ke `127.0.0.1:8088` — **tidak** exposed ke publik. TLS dan akses publik dihandle host-level reverse proxy (nginx/Caddy di luar docker) — lihat step #4. `backend`, `websocket`, mariadb, redis semua internal docker network only.

### Prerequisites di server

```text
- Docker + docker compose plugin terinstall
- Host nginx atau Caddy terinstall (untuk outer reverse proxy + TLS)
- Domain DNS A-record sudah mengarah ke IP server
- Port 80 dan 443 terbuka di firewall (untuk outer proxy)
- User yang menjalankan docker bukan root (tambahkan ke group docker)
```

### Step-by-step deployment

#### 1. Clone repo dan siapkan `.env`

```bash
git clone https://github.com/<your-org>/<your-repo> /opt/oak_app
cd /opt/oak_app
cp .env.example .env
```

Edit `.env` — wajib ganti:

```env
SITE_NAME=app.oakdepo.com                   # harus match Host header di healthcheck
ADMIN_PASSWORD=<random 24+ chars>           # generate: openssl rand -base64 24
MYSQL_ROOT_PASSWORD=<random 24+ chars>      # generate: openssl rand -base64 24
INSTALL_APPS=erpnext,hrms,erpnext_custom,container_depot,crm,helpdesk,raven,gameplan,telephony
```

`docker-compose.prod.yml` akan menolak jalan kalau `SITE_NAME`, `ADMIN_PASSWORD`, atau `MYSQL_ROOT_PASSWORD` kosong (di-enforce via `:?`).

#### 2. Build dan start stack (HTTP only dulu)

```bash
docker compose -f docker-compose.prod.yml build
docker compose -f docker-compose.prod.yml up -d
```

Pantau bootstrap:

```bash
docker compose -f docker-compose.prod.yml logs -f configurator
```

Tunggu sampai muncul `configured` di log. Configurator akan:

1. Tunggu database healthy
2. Buat site dengan nama `$SITE_NAME`
3. Install semua app di `INSTALL_APPS`
4. Migrate
5. Build assets

Setelah itu service lain (backend, websocket, workers) auto-start karena `depends_on: service_completed_successfully`.

#### 3. Verifikasi internal (HTTP via loopback)

Docker nginx di-bind ke `127.0.0.1:8088` — **tidak** exposed ke publik. Tes dari server itu sendiri (SSH dulu), bukan dari laptop:

```bash
curl -I --resolve app.oakdepo.com:8088:127.0.0.1 http://app.oakdepo.com:8088/api/method/ping
# expect: HTTP/1.1 200 OK
```

Note: `--resolve` perlu karena `SITE_NAME` di healthcheck dan Frappe site routing pakai `app.oakdepo.com`, sementara kita akses via `127.0.0.1`. `--resolve` paksa Host header `app.oakdepo.com` ke IP loopback.

Kalau OK, lanjut ke setup outer proxy. Belum bisa buka di browser sampai outer proxy + DNS + TLS jadi.

#### 4. Outer reverse proxy + TLS (host nginx atau Caddy)

**Arsitektur:**

```text
internet ─HTTPS─▶  host reverse proxy (TLS, port 443)
                   ─HTTP─▶  127.0.0.1:8088 (docker nginx)
                            ─HTTP─▶  backend:8000 (gunicorn)
```

TLS termination di host, **bukan** di docker. Docker nginx pure internal router. Pilihan outer proxy: host nginx (paling umum, butuh Certbot manual), atau Caddy (auto-TLS dari Let's Encrypt, paling sedikit config).

##### Opsi A: Caddy di host (recommended kalau server ini cuma untuk Oak)

Install:

```bash
sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | sudo tee /etc/apt/sources.list.d/caddy-stable.list
sudo apt update && sudo apt install caddy
```

`/etc/caddy/Caddyfile`:

```caddy
app.oakdepo.com {
    reverse_proxy 127.0.0.1:8088 {
        header_up X-Forwarded-Proto https
        header_up Host {host}
    }

    encode gzip
    log {
        output file /var/log/caddy/oak.log
    }
}
```

Apply:

```bash
sudo systemctl reload caddy
```

Caddy auto-fetch cert dari Let's Encrypt saat request pertama, auto-renew tanpa cron tambahan. Verifikasi:

```bash
curl -I https://app.oakdepo.com/api/method/ping
# expect: HTTP/1.1 200 OK + valid TLS cert
```

##### Opsi B: host nginx + Certbot (kalau sudah ada nginx di server)

```bash
sudo apt install -y nginx certbot python3-certbot-nginx
```

`/etc/nginx/sites-available/app.oakdepo.com`:

```nginx
server {
    listen 80;
    server_name app.oakdepo.com;

    location / {
        proxy_pass http://127.0.0.1:8088;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 120s;
        client_max_body_size 50m;
    }
}
```

Enable + obtain cert:

```bash
sudo ln -s /etc/nginx/sites-available/app.oakdepo.com /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
sudo certbot --nginx -d app.oakdepo.com --email you@yourdomain.com --agree-tos --no-eff-email --redirect
```

Certbot otomatis edit config nginx, install cert, set up auto-renewal via systemd timer (`systemctl list-timers | grep certbot`). Verifikasi:

```bash
curl -I https://app.oakdepo.com/api/method/ping
```

##### Catatan penting

- **SITE_NAME di `.env` harus sama persis dengan domain** (`app.oakdepo.com`). Healthcheck di [docker-compose.prod.yml](docker-compose.prod.yml) hardcode domain ini di header `Host:`. Mismatch = healthcheck fail terus = backend dianggap unhealthy = nginx dependency tidak start.
- Outer proxy **wajib** kirim `X-Forwarded-Proto: https` ke docker nginx. Tanpa ini, Frappe generate URL HTTP di email/redirect/reset link.
- Outer proxy juga handle HTTP→HTTPS redirect. Docker nginx tidak punya redirect logic — semuanya di outer.

#### 5. Backup otomatis

Tambah cron di host (sebagai user yang punya akses docker):

```bash
crontab -e
```

Tambahkan:

```cron
0 2 * * * cd /opt/oak_app && ./scripts/backup.sh >> /var/log/oak-backup.log 2>&1
```

Script jalanin `bench backup` di dalam container (tulis ke volume `bench-sites`), lalu `docker cp` artifact-nya keluar ke `./backups/` di host. Yang di-backup:

```text
<timestamp>-<site>-database.sql.gz     dump DB
<timestamp>-<site>-files.tar           public files (uploads)
<timestamp>-<site>-private-files.tar   private files
site_config.json                       <-- WAJIB, berisi encryption_key
```

**Penting**: `site_config.json` berisi `encryption_key`. Tanpa file ini, semua field Password di DocType TIDAK bisa di-decrypt saat restore. `backup.sh` sudah otomatis copy file ini ke folder backup.

Retensi lokal default 14 hari (atur via `BACKUP_RETENTION_DAYS` di `.env`). Untuk off-site (S3/B2/rclone), uncomment block di akhir `scripts/backup.sh`.

#### 6. Helper script untuk operasi harian prod

```text
scripts/prod-migrate.sh         bench migrate + clear-cache + clear-website-cache
scripts/prod-shell.sh [svc]     masuk container (default: backend)
scripts/prod-logs.sh [svc]      tail log (default: backend)
scripts/backup.sh               jalankan backup manual
```

### Update / deploy versi baru

```bash
cd /opt/oak_app
git pull

# kalau ada perubahan di Dockerfile / apps.json / app source yang baked:
docker compose -f docker-compose.prod.yml build

# naikkan container baru / apply compose env config:
docker compose -f docker-compose.prod.yml up -d

# kalau ada migration (DocType / fixture / patch):
scripts/prod-migrate.sh
```

Untuk zero-downtime sebenarnya butuh blue/green atau rolling — di luar scope repo ini.

#### Production asset refresh setelah `bench build`

Di production, Docker nginx hanya mount volume `bench-sites` sebagai read-only:

```text
bench-sites:/home/frappe/frappe-bench/sites:ro
```

Nginx **tidak** melihat app source di `/home/frappe/frappe-bench/apps`. Karena itu setelah `bench build`, asset dari `apps/<app>/<app>/public` harus dimaterialize/copy ke `sites/assets/<app>`. Kalau step ini terlewat, browser akan dapat banyak 404 untuk file seperti:

```text
/assets/frappe/dist/css/desk.bundle.<hash>.css
/assets/frappe/dist/js/desk.bundle.<hash>.js
/assets/erpnext/dist/css/erpnext.bundle.<hash>.css
/assets/hrms/dist/css/hrms.bundle.<hash>.css
/assets/raven/dist/css/raven.bundle.<hash>.css
/assets/frappe/icons/lucide/icons.svg
```

Jalankan sequence ini setelah build/migrate asset di prod:

```bash
cd /opt/oak_app

docker compose -p cakra_erpnext -f docker-compose.prod.yml exec backend bash -lc '
cd /home/frappe/frappe-bench
bench --site app.oakdepo.com migrate
bench build --apps frappe,erpnext,hrms,crm,helpdesk,raven,gameplan
MATERIALIZE_ASSETS=1 /usr/local/bin/build-assets.sh
bench --site app.oakdepo.com clear-cache
bench --site app.oakdepo.com clear-website-cache
'

docker compose -p cakra_erpnext -f docker-compose.prod.yml restart \
  backend websocket queue-short queue-default queue-long scheduler
```

Kenapa restart perlu: `bench build` mengubah hash file di `sites/assets/assets.json`. Gunicorn/Frappe bisa masih memegang manifest lama di memory. Restart runtime memastikan HTML baru mengarah ke hash asset baru.

Verifikasi asset dari server:

```bash
curl -I -H 'Host: app.oakdepo.com' http://127.0.0.1:8088/api/method/ping
curl -I -H 'Host: app.oakdepo.com' http://127.0.0.1:8088/assets/frappe/icons/lucide/icons.svg

# cek URL app frontend
curl -I -H 'Host: app.oakdepo.com' http://127.0.0.1:8088/helpdesk
curl -I -H 'Host: app.oakdepo.com' http://127.0.0.1:8088/raven
curl -I -H 'Host: app.oakdepo.com' http://127.0.0.1:8088/g
```

Catatan route:

```text
Helpdesk  /helpdesk
Raven     /raven
Gameplan  /g        # bukan /gameplan
CRM       /crm      # 403 berarti permission/setup issue, bukan asset/nginx
```

Setelah deploy asset, minta user hard refresh browser (`Ctrl+F5`) atau enable DevTools → Network → Disable cache → reload.

#### Update app source di prod (container_depot, erpnext_custom, dll.)

Beda dengan dev — di prod **tidak ada bind mount** app. Semua app di-bake ke image lewat `bench get-app` saat build (lihat [Dockerfile](Dockerfile)). Jadi edit kode di folder lokal `container_depot/` (atau app lain) tidak otomatis kepakai di prod sampai image di-rebuild.

Alurnya:

```bash
# 1. Di mesin dev — push perubahan ke GitHub repo app-nya
cd container_depot
git add -A && git commit -m "..." && git push origin main

# 2. Di server prod — rebuild image
cd /opt/oak_app
git pull   # opsional, kalau ada perubahan di repo oak_app

# WAJIB --no-cache di stage get-app, karena apps.json tidak berubah →
# Docker re-use layer lama dan TIDAK pull commit terbaru dari GitHub.
docker compose -f docker-compose.prod.yml build --no-cache backend

docker compose -f docker-compose.prod.yml up -d

# 3. Migrate kalau ada DocType / fixture / patch baru
scripts/prod-migrate.sh
```

Kapan butuh apa:

| Jenis perubahan app | Rebuild image | `up -d` | `prod-migrate.sh` |
| --- | --- | --- | --- |
| DocType / fixture / patch baru | ✓ (`--no-cache`) | ✓ | ✓ |
| Logic Python / API / controller | ✓ (`--no-cache`) | ✓ | — |
| Asset JS/CSS (app ada di `BUILD_APPS`) | ✓ (`--no-cache`) | ✓ | — |
| Hanya hooks.py / scheduled job | ✓ (`--no-cache`) | ✓ | — (cukup restart, sudah included di `up -d`) |

Catatan: `container_depot` dan `erpnext_custom` defaultnya ada di `SKIP_BUILD_APPS` ([docker-compose.prod.yml:78](docker-compose.prod.yml#L78)) — kalau menambah file di `public/`, pindahkan ke `BUILD_APPS` dulu lewat `.env`.

### Resource limits (recommended)

Default `docker-compose.prod.yml` tidak set memory/cpu limits — satu worker OOM bisa kill seluruh container. Tune berdasarkan spec server, uncomment block di `backend` service:

```yaml
deploy:
  resources:
    limits:
      memory: 2G
      cpus: "2.0"
```

Pattern serupa bisa diterapkan ke `queue-*`, `websocket`, `scheduler`. Mariadb butuh `innodb_buffer_pool_size` di-tune via command args kalau dataset > 1GB.

### Yang BELUM di-cover repo ini

| Item | Kenapa belum | Cara handle |
| --- | --- | --- |
| SMTP / Email Account | Per-deployment config | Set lewat desk: Email Account → New → SMTP |
| Off-site backup upload | Provider-specific | Uncomment block di `scripts/backup.sh` (rclone/aws) |
| CI/CD pipeline | Tooling-specific | Build image di CI, push ke registry, server pull |
| Multi-site | Bukan use case primary | Tambah `bench new-site` di init-site.sh |
| Frappe Cloud-style HA | Out of scope untuk single-server setup | Tidak applicable |

### Troubleshooting

```text
nginx 502 Bad Gateway          backend belum healthy → docker compose ps + logs backend
nginx 504 Gateway Timeout      gunicorn timeout → request berat, tune --timeout di compose
"App not in apps.txt"          init-site.sh harus regenerate, restart configurator
TLS error / cert expired       cek outer proxy (Caddy/host nginx), bukan docker — TLS di-handle di luar
Backup hanya nyimpan DB        cek backend running + ada disk space di host untuk docker cp
Setup wizard muncul terus      complete sekali lewat browser, atau bench setup-complete
```

---

## Useful Commands

Build image:

```bash
docker compose -f docker-compose.dev.yml build --no-cache frappe
```

Run development:

```bash
docker compose -f docker-compose.dev.yml up
```

Run production-like:

```bash
docker compose -f docker-compose.prod.yml up -d --build
```

View logs:

```bash
docker compose -f docker-compose.dev.yml logs -f
docker compose -f docker-compose.dev.yml logs -f frappe
```

Enter Frappe container jika service running:

```bash
docker compose -f docker-compose.dev.yml exec frappe bash
```

Jika service tidak running:

```bash
docker compose -f docker-compose.dev.yml run --rm frappe bash
```

Atau:

```bash
docker compose -f docker-compose.dev.yml run --rm --entrypoint bash frappe
```

---

## Bench Commands

Masuk container:

```bash
docker compose -f docker-compose.dev.yml exec frappe bash
cd /home/frappe/frappe-bench
```

List installed apps:

```bash
bench --site erp.localhost list-apps
```

Migrate:

```bash
bench --site erp.localhost migrate
```

Clear cache:

```bash
bench --site erp.localhost clear-cache
bench --site erp.localhost clear-website-cache
```

Install app manual:

```bash
bench --site erp.localhost install-app nama_app
```

Build asset manual:

```bash
build-assets.sh
```

Strict mode:

```bash
ASSET_STRICT=1 build-assets.sh
```

---

## Update App Source

### App yang di-mount (erpnext_custom, container_depot)

Edit di host langsung kepakai. Setelah `git pull` di folder app:

```bash
scripts/migrate.sh    # kalau ada perubahan DocType / fixture / patch
scripts/restart.sh    # kalau ada perubahan hooks.py / scheduled job
```

Tidak perlu rebuild image.

### App yang baked (frappe, erpnext, hrms, dll.)

Kalau mau update versi atau ganti branch di `apps.json`, rebuild image:

```bash
docker compose -f docker-compose.dev.yml build --no-cache frappe
docker compose -f docker-compose.dev.yml up -d
scripts/migrate.sh
```

Volume `bench-sites` tidak terhapus, jadi database dan site aman.

### Kapan harus rebuild image

```text
Dockerfile berubah                          rebuild
apps.json tambah/hapus app                  rebuild
Ganti branch frappe / erpnext / dll.        rebuild
Edit kode di erpnext_custom / container_depot   TIDAK perlu rebuild
```

---

## Reset Local Development

Hapus container dan volume:

```bash
docker compose -f docker-compose.dev.yml down -v --remove-orphans
```

Hapus image project:

```bash
docker image rm cakra-erpnext:dev || true
```

Jalankan ulang:

```bash
docker compose -f docker-compose.dev.yml up --build
```

> `down -v` menghapus database MariaDB dan site. Gunakan hanya untuk reset development.

---

## Docker Disk Cleanup on Windows + WSL2

Jika Docker Desktop memakai WSL2 backend, data Docker disimpan di file:

```text
C:\Users\<USERNAME>\AppData\Local\Docker\wsl\disk\docker_data.vhdx
```

Cek pemakaian Docker:

```bash
docker system df
```

Bersihkan Docker cache:

```bash
docker container prune -f
docker image prune -a -f
docker builder prune -a -f
```

Jika volume dev boleh dihapus:

```bash
docker volume prune -f
```

Jika `docker system df` sudah kecil tetapi file VHDX masih besar, lakukan compact dari PowerShell Administrator:

```powershell
wsl --shutdown
diskpart
```

Di `DISKPART>` jalankan satu per satu:

```powershell
select vdisk file="C:\Users\<USERNAME>\AppData\Local\Docker\wsl\disk\docker_data.vhdx"
attach vdisk readonly
compact vdisk
detach vdisk
exit
```

---

## Common Issues

### `error getting credentials`

Biasanya terjadi setelah reset Docker Desktop.

Fix di WSL:

```bash
mkdir -p ~/.docker
mv ~/.docker/config.json ~/.docker/config.json.bak 2>/dev/null || true

cat > ~/.docker/config.json <<'EOF'
{
  "auths": {}
}
EOF
```

Lalu:

```bash
docker pull mariadb:10.8
```

### `service "frappe" is not running`

Gunakan `run --rm` bukan `exec`:

```bash
docker compose -f docker-compose.dev.yml run --rm frappe bash
```

### `App erpnext not in apps.txt`

Biasanya karena folder `sites/` tertutup Docker volume. `init-site.sh` harus regenerate `sites/apps.txt` dari folder `apps/`.

### `NoneType object is not subscriptable` saat install custom app

Pastikan `erpnext_custom/hooks.py` punya metadata minimal:

```python
app_name = "erpnext_custom"
app_title = "ERPNext Custom"
app_publisher = "Cakra ERPNext Apps"
app_description = "Customizations for ERPNext"
app_email = "admin@example.com"
app_license = "MIT"

required_apps = ["frappe", "erpnext", "hrms"]
```

### Asset build error

Jika app tertentu gagal saat asset build, tambahkan ke:

```env
SKIP_BUILD_APPS=erpnext_custom,nama_app
```

Jika ingin build gagal membuat container stop, gunakan:

```env
ASSET_STRICT=1
```

Untuk development, gunakan:

```env
ASSET_STRICT=0
```

### 404 di bundle assets (desk/erpnext/hrms .css/.js) setelah migrate atau test

Gejala: browser console penuh `GET /assets/frappe/dist/js/desk.bundle.XXXXXXXX.js 404 NOT FOUND`, halaman desk tidak load, error `Error restoring session : Transport request timed out`. Muncul setelah jalan `scripts/migrate.sh` atau `scripts/test.sh`.

Penyebab: `bench start` punya asset watcher yang rebuild bundle dengan **content hash baru** setiap kali file frontend berubah. Saat `bench migrate` / `bench run-tests` memicu regenerasi (mis. doctype baru menyentuh file), hash di disk berubah. Dengan `developer_mode=0`, Frappe cache mapping `assets.json` di shared Redis (`bench_cache_keys = ("assets_json",)` di `apps/frappe/frappe/cache_manager.py`). HTML di-render pakai hash lama dari cache → file dengan hash itu sudah tidak ada di disk → 404.

Fix permanen (sudah ada di repo):

1. `DEVELOPER_MODE=1` di [docker-compose.dev.yml](docker-compose.dev.yml) — `get_assets_json()` skip cache, selalu baca disk.
2. `scripts/migrate.sh` dan `scripts/test.sh` selalu jalankan `bench clear-cache && bench clear-website-cache` setelah perintah utamanya.

Fix manual kalau site lama belum punya `developer_mode`:

```bash
docker compose -f docker-compose.dev.yml exec frappe \
  bash -c 'bench set-config -gp developer_mode 1 \
    && bench --site "$SITE_NAME" clear-cache \
    && bench --site "$SITE_NAME" clear-website-cache'
```

Lalu hard refresh browser (Ctrl+Shift+R). **Jangan** aktifkan `developer_mode=1` di prod — itu mematikan banyak caching dan expose traceback. Untuk prod, `clear-cache` di `scripts/prod-migrate.sh` sudah cukup.

---

## Git Repository Recommendation

Sebaiknya buat repo baru khusus Docker/deployment, misalnya:

```text
cakra-erpnext-docker
```

`.gitignore` yang disarankan:

```gitignore
.env
*.log
resolving
unpacking

frappe/
erpnext/
hrms/
crm/
helpdesk/
raven/
gameplan/
telephony/
erpnext_custom/

sites/
logs/
node_modules/
__pycache__/
```

Inisialisasi repo:

```bash
git init
git add Dockerfile docker-compose.dev.yml docker-compose.prod.yml apps.json README.md scripts .gitignore .env.example
git commit -m "Initial Docker setup for Cakra ERPNext"
git branch -M main
git remote add origin https://github.com/cakra-erpnext-apps/cakra-erpnext-docker.git
git push -u origin main
```

---

## Notes

- Jangan commit `.env`. Gunakan `.env.example`.
- Jangan commit folder app hasil clone.
- Jangan commit volume, database, logs, atau node_modules.
- Untuk development, `ASSET_STRICT=0` lebih nyaman.
- Untuk production/staging, gunakan `ASSET_STRICT=1`.
- Untuk production publik, gunakan reverse proxy dan SSL.
- Jika install semua app sekaligus, pisahkan `INSTALL_APPS`, `BUILD_APPS`, dan `SKIP_BUILD_APPS` supaya troubleshooting lebih mudah.
