# Cakra ERPNext Docker Setup

Setup ini digunakan untuk menjalankan ERPNext/Frappe dari fork repository milik `cakra-erpnext-apps` menggunakan Docker.

Target utama setup ini:

- Local development ERPNext/Frappe
- Mudah update app dari fork GitHub
- Bisa dijadikan dasar untuk staging/production
- Mendukung custom app seperti `erpnext_custom`

---

## Struktur Folder

Contoh struktur project:

```text
oak_app/
├── apps.json
├── Dockerfile
├── docker-compose.yml
├── .env
├── scripts/
│   └── init-site.sh
├── frappe/
├── erpnext/
├── erpnext_custom/
├── hrms/
├── crm/
├── helpdesk/
├── raven/
├── gameplan/
└── telephony/
```

Catatan:

- `frappe` digunakan sebagai framework utama saat `bench init`.
- App lain seperti `erpnext`, `hrms`, dan `erpnext_custom` di-install ke site menggunakan `bench install-app`.
- Untuk awal development, install app core dulu: `erpnext`, `hrms`, dan `erpnext_custom`.

---

## Repository yang Digunakan

Semua app diasumsikan sudah di-fork ke organization:

```text
https://github.com/cakra-erpnext-apps
```

Repository utama:

```text
frappe
erpnext
hrms
crm
helpdesk
raven
gameplan
telephony
erpnext_custom
```

Untuk Frappe/ERPNext v16, pastikan branch utama memakai:

```text
frappe  -> version-16
erpnext -> version-16
hrms    -> version-16
```

App lain bisa memakai branch sesuai kebutuhan, misalnya `main` atau `develop`, tapi tetap perlu dicek kompatibilitasnya dengan Frappe v16.

---

## File `.env`

Buat file `.env` di root project:

```env
COMPOSE_PROJECT_NAME=cakra_erpnext

SITE_NAME=erp.localhost
ADMIN_PASSWORD=admin
MYSQL_ROOT_PASSWORD=123

FRAPPE_REPO=https://github.com/cakra-erpnext-apps/frappe
FRAPPE_BRANCH=version-16

INSTALL_APPS=erpnext,hrms,erpnext_custom
```

Untuk awal, jangan langsung install semua app. Gunakan dulu:

```env
INSTALL_APPS=erpnext,hrms,erpnext_custom
```

Setelah core berhasil jalan, baru bisa coba app tambahan:

```env
INSTALL_APPS=erpnext,hrms,erpnext_custom,crm,helpdesk,raven,gameplan,telephony
```

---

## File `apps.json`

File ini berisi daftar app yang akan diambil saat build image.

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

## Cara Menjalankan Local Development

Pastikan posisi terminal berada di root project:

```bash
cd oak_app
```

Jalankan Docker Compose:

```bash
docker compose up --build
```

Atau kalau ingin menjalankan di background:

```bash
docker compose up -d --build
```

Buka browser:

```text
http://localhost:8000
```

Login default:

```text
Username: Administrator
Password: admin
```

Password mengikuti value `ADMIN_PASSWORD` di file `.env`.

---

## Service yang Digunakan

Di `docker-compose.yml`, service utama yang digunakan:

```text
mariadb
redis-cache
redis-queue
redis-socketio
frappe
```

Fungsi masing-masing:

| Service | Fungsi |
|---|---|
| `mariadb` | Database ERPNext/Frappe |
| `redis-cache` | Cache Frappe |
| `redis-queue` | Queue/background jobs |
| `redis-socketio` | Realtime/socket.io |
| `frappe` | Container utama untuk menjalankan bench |

Untuk local development, container `frappe` menjalankan:

```bash
bench start
```

---

## Perintah Docker yang Sering Dipakai

Build dan jalankan container:

```bash
docker compose up --build
```

Jalankan di background:

```bash
docker compose up -d --build
```

Lihat log:

```bash
docker compose logs -f
```

Lihat log service Frappe saja:

```bash
docker compose logs -f frappe
```

Masuk ke container Frappe:

```bash
docker compose exec frappe bash
```

Stop container:

```bash
docker compose down
```

Stop dan hapus volume database/site:

```bash
docker compose down -v
```

Hati-hati: command `down -v` akan menghapus data MariaDB dan site.

---

## Bench Command di Dalam Container

Masuk dulu ke container:

```bash
docker compose exec frappe bash
```

Lalu jalankan command dari folder bench:

```bash
cd /home/frappe/frappe-bench
```

Migrate site:

```bash
bench --site erp.localhost migrate
```

Clear cache:

```bash
bench --site erp.localhost clear-cache
```

Clear website cache:

```bash
bench --site erp.localhost clear-website-cache
```

Install app manual:

```bash
bench --site erp.localhost install-app nama_app
```

Contoh:

```bash
bench --site erp.localhost install-app crm
```

Lihat app yang sudah terinstall:

```bash
bench --site erp.localhost list-apps
```

---

## Cara Update Development

Jika ada perubahan di repository fork, rebuild image:

```bash
docker compose build --no-cache frappe
```

Lalu jalankan ulang:

```bash
docker compose up -d
```

Setelah itu migrate:

```bash
docker compose exec frappe bash
cd /home/frappe/frappe-bench
bench --site erp.localhost migrate
```

---

## Cara Menambah App Baru

1. Tambahkan app ke `apps.json`:

```json
{
  "name": "nama_app",
  "url": "https://github.com/cakra-erpnext-apps/nama_app",
  "branch": "main"
}
```

2. Rebuild image:

```bash
docker compose build --no-cache frappe
```

3. Tambahkan nama app ke `.env`:

```env
INSTALL_APPS=erpnext,hrms,erpnext_custom,nama_app
```

4. Jalankan ulang container:

```bash
docker compose up -d
```

5. Install manual jika belum otomatis:

```bash
docker compose exec frappe bash
cd /home/frappe/frappe-bench
bench --site erp.localhost install-app nama_app
bench --site erp.localhost migrate
```

---

## Catatan Branch

Karena setup ini memakai Frappe v16, pastikan branch app utama konsisten:

```text
frappe  : version-16
erpnext : version-16
hrms    : version-16
```

App seperti `crm`, `helpdesk`, `raven`, `gameplan`, dan `telephony` bisa saja memakai `main` atau `develop`, tetapi jika muncul error dependency, kemungkinan branch app tersebut belum cocok dengan Frappe v16.

Rekomendasi urutan install:

```text
1. frappe version-16
2. erpnext version-16
3. hrms version-16
4. erpnext_custom main
5. crm main
6. helpdesk main
7. raven main
8. gameplan main
9. telephony develop
```

---

## Troubleshooting

### Error: file `docker-compose.dev.yml` tidak ditemukan

Jika file kamu bernama:

```text
docker-compose.yml
```

Jangan jalankan:

```bash
docker compose -f docker-compose.dev.yml up --build
```

Gunakan:

```bash
docker compose up --build
```

atau:

```bash
docker compose -f docker-compose.yml up --build
```

---

### Error site sudah ada

Jika site sudah pernah dibuat, script `init-site.sh` harus melewati proses `bench new-site` dan langsung menggunakan site tersebut.

Cek site:

```bash
docker compose exec frappe bash
ls /home/frappe/frappe-bench/sites
```

---

### Reset semua data local

Gunakan hanya jika ingin mulai dari nol:

```bash
docker compose down -v
```

Lalu jalankan ulang:

```bash
docker compose up --build
```

---

### App belum terinstall di site

Masuk ke container:

```bash
docker compose exec frappe bash
cd /home/frappe/frappe-bench
```

Install app:

```bash
bench --site erp.localhost install-app nama_app
bench --site erp.localhost migrate
```

---

## Catatan Production

Setup ini cocok untuk local development dan staging awal.

Untuk production, sebaiknya service dipisah menjadi:

```text
backend
frontend / reverse proxy
websocket
queue-short
queue-default
queue-long
scheduler
mariadb
redis-cache
redis-queue
redis-socketio
```

Untuk production juga disarankan memakai reverse proxy seperti Nginx, Caddy, atau Traefik di depan service Frappe, serta menggunakan SSL domain.

Pola update production yang disarankan:

```text
1. Pull perubahan dari repository
2. Build image baru
3. Restart container
4. Jalankan migrate
5. Cek log dan fitur utama
```

Contoh:

```bash
git pull
docker compose build --no-cache
docker compose up -d
docker compose exec frappe bash
cd /home/frappe/frappe-bench
bench --site erp.localhost migrate
```

---

## Important Notes

- Jangan campur branch `version-15`, `version-16`, `main`, dan `develop` sembarangan tanpa cek kompatibilitas.
- Untuk awal, install app core dulu.
- Jangan sering memakai `docker compose down -v` kecuali memang ingin menghapus semua data.
- Jika app custom punya dependency ke app lain, pastikan app dependency sudah di-install lebih dulu.
- Untuk production, jangan mengedit langsung container. Update harus lewat repository dan rebuild image.
