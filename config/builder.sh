#!/bin/bash
set -euo pipefail

BASE_DIR="/opt/auto-backup"
CONFIG="$BASE_DIR/config.conf"

mkdir -p "$BASE_DIR"

if [[ ! -f "$CONFIG" ]]; then
    echo "[ERROR] config.conf tidak ditemukan!"
    exit 1
fi

# ------------------------------------------
# LOAD CONFIG
# ------------------------------------------
# shellcheck source=/dev/null
source "$CONFIG"

# assign safe defaults
BOT_TOKEN="${BOT_TOKEN:-}"
CHAT_ID="${CHAT_ID:-}"
FOLDERS_RAW="${FOLDERS_RAW:-}"
USE_MYSQL="${USE_MYSQL:-n}"
USE_MONGO="${USE_MONGO:-n}"
USE_PG="${USE_PG:-n}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
TZ="${TZ:-Asia/Jakarta}"
INSTALL_DIR="${INSTALL_DIR:-$BASE_DIR}"

# ------------------------------------------
# VALIDASI MINIMAL
# ------------------------------------------

if [[ -z "$BOT_TOKEN" ]]; then
    echo "[WARN] BOT_TOKEN kosong."
fi

if [[ -z "$CHAT_ID" ]]; then
    echo "[WARN] CHAT_ID kosong."
fi

if [[ -z "$FOLDERS_RAW" ]]; then
    echo "[WARN] FOLDER backup kosong."
fi

# ------------------------------------------
# GENERATE INTERNAL CONFIG FORMAT
# (MySQL / Mongo / PostgreSQL tetap mengikuti format file lama)
# ------------------------------------------

MYSQL_MULTI_CONF="${MYSQL_MULTI_CONF:-}"
MONGO_MULTI_CONF="${MONGO_MULTI_CONF:-}"

# jika MySQL aktif tapi belum ada konfigurasi
if [[ "$USE_MYSQL" == "y" && -z "$MYSQL_MULTI_CONF" ]]; then
    echo "[INFO] MySQL aktif tetapi belum ada konfigurasi."
fi

if [[ "$USE_MONGO" == "y" && -z "$MONGO_MULTI_CONF" ]]; then
    echo "[INFO] MongoDB aktif tetapi belum ada konfigurasi."
fi

# PostgreSQL otomatis, tidak perlu format tambahan

# ------------------------------------------
# SIMPAN KEMBALI CONFIG (distandarkan)
# ------------------------------------------

cat > "$CONFIG" <<EOF
BOT_TOKEN="$BOT_TOKEN"
CHAT_ID="$CHAT_ID"
FOLDERS_RAW="$FOLDERS_RAW"

USE_MYSQL="$USE_MYSQL"
MYSQL_MULTI_CONF="$MYSQL_MULTI_CONF"

USE_MONGO="$USE_MONGO"
MONGO_MULTI_CONF="$MONGO_MULTI_CONF"

USE_PG="$USE_PG"
RETENTION_DAYS="$RETENTION_DAYS"
TZ="$TZ"
INSTALL_DIR="$INSTALL_DIR"
EOF

chmod 600 "$CONFIG"

echo "[OK] builder.sh: config distandardisasi."
