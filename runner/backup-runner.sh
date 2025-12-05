#!/bin/bash
set -euo pipefail

# backup-runner.sh
# - Jika dipanggil dengan --build => buat struktur direktori & cek dependensi (tidak menjalankan backup)
# - Jika dipanggil tanpa arg => jalankan proses backup sesuai config.conf

BASE_DIR="/opt/auto-backup"
CONFIG_FILE="$BASE_DIR/config.conf"
BACKUP_DIR="$BASE_DIR/backups"
TMPROOT="$BASE_DIR"

# helper
log() { echo "[$(date '+%F %T')] $*"; }

if [[ "${1:-}" == "--build" ]]; then
    mkdir -p "$BASE_DIR" "$BACKUP_DIR" "$BASE_DIR/tmp"
    chmod 755 "$BASE_DIR"
    chmod 700 "$CONFIG_FILE" 2>/dev/null || true
    log "Build mode: struktur direktori dibuat/di-check."
    exit 0
fi

# ---------- load config ----------
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "[ERROR] Config not found: $CONFIG_FILE"
    exit 1
fi
# shellcheck source=/dev/null
source "$CONFIG_FILE"

# ensure safe defaults
BOT_TOKEN="${BOT_TOKEN:-}"
CHAT_ID="${CHAT_ID:-}"
FOLDERS_RAW="${FOLDERS_RAW:-}"
USE_MYSQL="${USE_MYSQL:-n}"
MYSQL_MULTI_CONF="${MYSQL_MULTI_CONF:-}"
USE_MONGO="${USE_MONGO:-n}"
MONGO_MULTI_CONF="${MONGO_MULTI_CONF:-}"
USE_PG="${USE_PG:-n}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
TZ="${TZ:-UTC}"
INSTALL_DIR="${INSTALL_DIR:-$BASE_DIR}"

export TZ

mkdir -p "$BACKUP_DIR"
DATE=$(date +%F-%H%M%S)
TMP_DIR="$TMPROOT/tmp-$DATE"
mkdir -p "$TMP_DIR"

log "Mulai backup: $DATE"
log "Temporary dir: $TMP_DIR"

# ---------- backup folders ----------
if [[ -n "$FOLDERS_RAW" ]]; then
    IFS=',' read -r -a FOLDERS <<< "$FOLDERS_RAW"
    for f in "${FOLDERS[@]}"; do
        f_trimmed=$(echo "$f" | xargs)
        if [[ -d "$f_trimmed" ]]; then
            # copy preserving attributes, but skip problematic mounts to avoid hanging
            cp -a --preserve=mode,ownership,timestamps "$f_trimmed" "$TMP_DIR/" 2>/dev/null || {
                log "Warn: gagal copy $f_trimmed (melanjutkan)"
            }
        else
            log "Info: folder tidak ditemukan, lewati: $f_trimmed"
        fi
    done
else
    log "Info: tidak ada folder untuk dibackup."
fi

# ---------- backup MySQL (multi) ----------
if [[ "${USE_MYSQL}" == "y" && -n "${MYSQL_MULTI_CONF}" ]]; then
    mkdir -p "$TMP_DIR/mysql"
    IFS=';' read -r -a ITEMS <<< "$MYSQL_MULTI_CONF"
    for ITEM in "${ITEMS[@]}"; do
        # format: user:pass@host:dbs
        USERPASS=$(echo "$ITEM" | cut -d'@' -f1)
        HOSTPART=$(echo "$ITEM" | cut -d'@' -f2)
        MYSQL_USER=$(echo "$USERPASS" | cut -d':' -f1)
        MYSQL_PASS=$(echo "$USERPASS" | cut -d':' -f2)
        MYSQL_HOST=$(echo "$HOSTPART" | cut -d':' -f1)
        MYSQL_DBLIST=$(echo "$HOSTPART" | cut -d':' -f2)

        MYSQL_ARGS="-h${MYSQL_HOST} -u${MYSQL_USER} -p${MYSQL_PASS}"

        if ! command -v mysqldump >/dev/null 2>&1; then
            log "Warn: mysqldump tidak ditemukan. Melewatkan MySQL dump untuk $MYSQL_HOST"
            continue
        fi

        if [[ "$MYSQL_DBLIST" == "all" ]]; then
            OUT="$TMP_DIR/mysql/${MYSQL_USER}@${MYSQL_HOST}_ALL.sql"
            mysqldump ${MYSQL_ARGS} --all-databases > "$OUT" 2>/dev/null || log "Warn: mysqldump gagal untuk $MYSQL_HOST (all)"
        else
            IFS=',' read -r -a DARR <<< "$MYSQL_DBLIST"
            for DB in "${DARR[@]}"; do
                DB=$(echo "$DB" | xargs)
                OUT="$TMP_DIR/mysql/${MYSQL_USER}@${MYSQL_HOST}_${DB}.sql"
                mysqldump ${MYSQL_ARGS} "$DB" > "$OUT" 2>/dev/null || log "Warn: mysqldump gagal untuk $MYSQL_HOST/$DB"
            done
        fi
    done
else
    log "MySQL: non-aktif atau tidak ada konfigurasi."
fi

# ---------- backup MongoDB (multi) ----------
if [[ "${USE_MONGO}" == "y" && -n "${MONGO_MULTI_CONF}" ]]; then
    mkdir -p "$TMP_DIR/mongo"
    IFS=';' read -r -a ITEMS <<< "$MONGO_MULTI_CONF"
    for ITEM in "${ITEMS[@]}"; do
        # format: user:pass@host:port:authdb:dbs
        CREDS=$(echo "$ITEM" | cut -d'@' -f1)
        HOSTPART=$(echo "$ITEM" | cut -d'@' -f2)
        MONGO_USER=$(echo "$CREDS" | cut -d':' -f1)
        MONGO_PASS=$(echo "$CREDS" | cut -d':' -f2)
        MONGO_HOST=$(echo "$HOSTPART" | cut -d':' -f1)
        MONGO_PORT=$(echo "$HOSTPART" | cut -d':' -f2)
        MONGO_AUTHDB=$(echo "$HOSTPART" | cut -d':' -f3)
        MONGO_DB_LIST=$(echo "$HOSTPART" | cut -d':' -f4)

        SAFE_NAME=$(echo "${MONGO_USER}_${MONGO_HOST}_${MONGO_PORT}" | sed 's/[^a-zA-Z0-9._-]/_/g')
        DEST="$TMP_DIR/mongo/$SAFE_NAME"
        mkdir -p "$DEST"

        if ! command -v mongodump >/dev/null 2>&1; then
            log "Warn: mongodump tidak ditemukan. Melewatkan Mongo dump untuk $MONGO_HOST:$MONGO_PORT"
            continue
        fi

        BASE_ARGS="--host=${MONGO_HOST} --port=${MONGO_PORT} --out=${DEST}"
        if [[ -n "$MONGO_USER" ]]; then
            BASE_ARGS="$BASE_ARGS --username=${MONGO_USER} --password='${MONGO_PASS}' --authenticationDatabase=${MONGO_AUTHDB}"
        fi

        if [[ "$MONGO_DB_LIST" == "all" ]]; then
            # dump all
            eval mongodump $BASE_ARGS || log "Warn: mongodump gagal untuk $MONGO_HOST (all)"
        else
            IFS=',' read -r -a MDBARR <<< "$MONGO_DB_LIST"
            for MDB in "${MDBARR[@]}"; do
                MDB=$(echo "$MDB" | xargs)
                eval mongodump $BASE_ARGS --db="${MDB}" || log "Warn: mongodump gagal $MONGO_HOST/$MDB"
            done
        fi

        # compress this mongo dump folder for smaller archive
        if [[ -d "$DEST" ]]; then
            tar -czf "${DEST}.tar.gz" -C "$DEST" . || log "Warn: compress mongo dump gagal untuk $DEST"
            rm -rf "$DEST"
        fi
    done
else
    log "MongoDB: non-aktif atau tidak ada konfigurasi."
fi

# ---------- backup PostgreSQL ----------
if [[ "${USE_PG}" == "y" ]]; then
    mkdir -p "$TMP_DIR/postgres"
    if id -u postgres >/dev/null 2>&1; then
        if command -v pg_dumpall >/dev/null 2>&1; then
            su - postgres -c "pg_dumpall > $TMP_DIR/postgres/all.sql" || log "Warn: pg_dumpall gagal"
        else
            log "Warn: pg_dumpall tidak ditemukan."
        fi
    else
        log "Warn: user 'postgres' tidak ada. Melewatkan PG dump."
    fi
else
    log "PostgreSQL: non-aktif."
fi

# ---------- create archive ----------
ARCHIVE="$BACKUP_DIR/backup-$DATE.tar.gz"
tar -czf "$ARCHIVE" -C "$TMP_DIR" . || {
    log "ERROR: gagal membuat archive"
    rm -rf "$TMP_DIR"
    exit 1
}

log "Archive dibuat: $ARCHIVE"

# ---------- send to Telegram (document) ----------
if [[ -n "$BOT_TOKEN" && -n "$CHAT_ID" ]]; then
    if command -v curl >/dev/null 2>&1; then
        # use multipart/form-data
        curl -s -F document=@"$ARCHIVE"              -F caption="Backup selesai: $(basename "$ARCHIVE")"              "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument?chat_id=${CHAT_ID}"              >/dev/null 2>&1 || log "Warn: gagal kirim ke Telegram (curl error)"
        log "Mengirim ke Telegram: selesai (attempted)."
    else
        log "Warn: curl tidak tersedia. Tidak dapat mengirim ke Telegram."
    fi
else
    log "Info: BOT_TOKEN/CHAT_ID kosong; melewatkan kirim ke Telegram."
fi

# ---------- cleanup temp ----------
rm -rf "$TMP_DIR"
log "Temporary dir dihapus: $TMP_DIR"

# ---------- retention ----------
if [[ -n "$RETENTION_DAYS" ]]; then
    find "$BACKUP_DIR" -type f -mtime +"$RETENTION_DAYS" -print -delete || log "Warn: retention cleanup gagal"
    log "Retention: file lebih tua dari $RETENTION_DAYS hari dihapus."
fi

log "Backup selesai: $ARCHIVE"
exit 0
