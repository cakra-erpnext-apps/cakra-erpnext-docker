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

## Production-like / Staging

Jalankan:

```bash
docker compose -f docker-compose.prod.yml up -d --build
```

Service production-like:

```text
mariadb
redis-cache
redis-queue
redis-socketio
configurator
backend
websocket
queue-short
queue-default
queue-long
scheduler
```

`configurator` menjalankan:

```bash
init-site.sh build-assets.sh && echo configured
```

Service lain menunggu `configurator` selesai dengan sukses menggunakan:

```yaml
condition: service_completed_successfully
```

Jika belum memakai reverse proxy, backend diexpose ke:

```text
http://SERVER_IP:8000
```

Websocket diexpose ke:

```text
SERVER_IP:9000
```

Untuk production publik, tambahkan reverse proxy dan SSL.

---

## Reverse Proxy Recommendation

Untuk production publik, gunakan Nginx/Caddy/Traefik.

Route minimal:

```text
https://domain.com        -> backend:8000
/socket.io               -> websocket:9000
/assets                  -> backend/static files
/files                   -> backend/site files
```

Setup reverse proxy belum disertakan di repo ini.

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

Jika ada update di fork GitHub:

```bash
docker compose -f docker-compose.dev.yml down
docker compose -f docker-compose.dev.yml build --no-cache frappe
docker compose -f docker-compose.dev.yml up
```

Jika hanya ingin rebuild tanpa menghapus data:

```bash
docker compose -f docker-compose.dev.yml build --no-cache frappe
docker compose -f docker-compose.dev.yml up -d
```

Lalu migrate:

```bash
docker compose -f docker-compose.dev.yml exec frappe bash
cd /home/frappe/frappe-bench
bench --site erp.localhost migrate
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
