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
scripts/migrate.sh           bench --site $SITE_NAME migrate
scripts/restart.sh           docker compose restart frappe
scripts/shell.sh             masuk container (exec kalau running, run --rm kalau tidak)
scripts/logs.sh [service]    tail logs, default service = frappe
scripts/test.sh [app]        bench run-tests --app, default app = erpnext_custom
```

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
