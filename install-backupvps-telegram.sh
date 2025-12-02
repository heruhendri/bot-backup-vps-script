#!/bin/bash
set -euo pipefail
clear

WATERMARK_INSTALL="=== AUTO BACKUP VPS — INSTALLER v21 ===
Installer by: HENDRI
Support: https://t.me/GbtTapiPngnSndiri
========================================="
WATERMARK_END="=== INSTALL COMPLETE — SCRIPT BY HENDRI ===
Support: https://t.me/GbtTapiPngnSndiri
========================================="

echo "$WATERMARK_INSTALL"
echo ""

INSTALL_DIR="/opt/auto-backup"
CONFIG_FILE="$INSTALL_DIR/config.conf"
MENU_FILE="$INSTALL_DIR/menu.sh"
RUNNER="$INSTALL_DIR/backup-runner.sh"
SERVICE_FILE="/etc/systemd/system/auto-backup.service"
TIMER_FILE="/etc/systemd/system/auto-backup.timer"

mkdir -p "$INSTALL_DIR"
chmod 755 "$INSTALL_DIR"

#############################################
# 1. ROOT CHECK
#############################################
if [[ "$(id -u)" -ne 0 ]]; then
    echo "[ERROR] Script harus dijalankan sebagai root!"
    exit 1
fi

#############################################
# 2. CEK BASIC DEPENDENCY
#############################################
for cmd in systemctl curl rsync tar; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "[WARN] Dependency hilang: $cmd — sebaiknya install dulu."
    fi
done

#############################################
# 3. CONFIG MODE (NEW / UPDATE)
#############################################
if [[ -f "$CONFIG_FILE" ]]; then
    echo "[INFO] Config ditemukan: $CONFIG_FILE"
    read -p "Update config? (y/N): " c
    [[ "${c,,}" == "y" ]] && UPDATE_CONFIG="y" || UPDATE_CONFIG="n"
else
    UPDATE_CONFIG="y"
fi

#############################################
# 4. INPUT CONFIG BARU
#############################################
if [[ "$UPDATE_CONFIG" == "y" ]]; then
    echo ""
    read -p "BOT TOKEN Telegram       : " BOT_TOKEN
    read -p "CHAT_ID Telegram         : " CHAT_ID
    read -p "Folder backup (comma)    : " FOLDERS_RAW

    read -p "Backup MySQL? (y/n)      : " USE_MYSQL
    MYSQL_MULTI_CONF=""

    if [[ "$USE_MYSQL" == "y" ]]; then
        read -p "Jumlah konfigurasi MySQL : " MYSQL_COUNT
        MYSQL_COUNT=${MYSQL_COUNT:-0}

        for ((i=1; i<=MYSQL_COUNT; i++)); do
            echo ""
            echo "[MySQL #$i]"
            read -p "Host (default: localhost): " MYSQL_HOST
            MYSQL_HOST=${MYSQL_HOST:-localhost}

            read -p "User: " MYSQL_USER
            read -s -p "Pass: " MYSQL_PASS
            echo ""

            echo "Mode DB: 1=all, 2=pilih"
            read -p "Pilih mode: " m
            if [[ "$m" == "1" ]]; then
                DBLIST="all"
            else
                read -p "Daftar DB (comma): " DBLIST
            fi

            ENTRY="${MYSQL_USER}:${MYSQL_PASS}@${MYSQL_HOST}:${DBLIST}"
            [[ -z "$MYSQL_MULTI_CONF" ]] && MYSQL_MULTI_CONF="$ENTRY" || MYSQL_MULTI_CONF="$MYSQL_MULTI_CONF;$ENTRY"
        done
    fi

    read -p "Backup PostgreSQL? (y/n) : " USE_PG
    read -p "Retention days (default 3): " RETENTION_DAYS
    RETENTION_DAYS=${RETENTION_DAYS:-3}

    read -p "Timezone (Asia/Jakarta)   : " TZ
    TZ=${TZ:-Asia/Jakarta}

    read -p "Jadwal OnCalendar (*-*-* 03:00:00): " CRON_TIME
    CRON_TIME=${CRON_TIME:-"*-*-* 03:00:00"}

    timedatectl set-timezone "$TZ" 2>/dev/null || true

    #############################################
    # SIMPAN CONFIG
    #############################################
    cat > "$CONFIG_FILE" <<EOF
BOT_TOKEN="$BOT_TOKEN"
CHAT_ID="$CHAT_ID"
FOLDERS_RAW="$FOLDERS_RAW"
USE_MYSQL="$USE_MYSQL"
MYSQL_MULTI_CONF="$MYSQL_MULTI_CONF"
USE_PG="$USE_PG"
RETENTION_DAYS="$RETENTION_DAYS"
TZ="$TZ"
INSTALL_DIR="$INSTALL_DIR"
CRON_TIME="$CRON_TIME"
EOF

    chmod 600 "$CONFIG_FILE"
else
    source "$CONFIG_FILE"
fi

#############################################
# 5. SET DEFAULT VALUE (ANTI ERROR)
#############################################
BOT_TOKEN="${BOT_TOKEN:-}"
CHAT_ID="${CHAT_ID:-}"
FOLDERS_RAW="${FOLDERS_RAW:-}"
USE_MYSQL="${USE_MYSQL:-n}"
MYSQL_MULTI_CONF="${MYSQL_MULTI_CONF:-}"
USE_PG="${USE_PG:-n}"
RETENTION_DAYS="${RETENTION_DAYS:-3}"
TZ="${TZ:-Asia/Jakarta}"
INSTALL_DIR="${INSTALL_DIR:-/opt/auto-backup}"
CRON_TIME="${CRON_TIME:-"*-*-* 03:00:00"}"

#############################################
# 6. BUAT BACKUP-RUNNER (v21)
#############################################
# versi ini otomatis memasukkan RUNNER v21
curl -s https://raw.githubusercontent.com/H4X3Y/backupvps-runner21/main/runner.sh -o "$RUNNER" 2>/dev/null \
    || {
        echo "[ERROR] Gagal mengambil backup-runner. Cek internet."
        exit 1
    }

chmod +x "$RUNNER"
echo "[OK] Backup-runner (v21) terpasang."

#############################################
# 7. SYSTEMD SERVICE
#############################################
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Auto Backup VPS to Telegram
After=network-online.target

[Service]
Type=oneshot
Environment="TZ=$TZ"
ExecStart=$RUNNER
User=root

[Install]
WantedBy=multi-user.target
EOF

#############################################
# 8. SYSTEMD TIMER
#############################################
cat > "$TIMER_FILE" <<EOF
[Unit]
Description=Schedule Auto Backup VPS

[Timer]
OnCalendar=$CRON_TIME
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now auto-backup.timer
systemctl enable auto-backup.service

echo "[OK] Systemd service & timer diaktifkan."

#############################################
# 9. INSTAL MENU
#############################################
curl -s https://raw.githubusercontent.com/H4X3Y/backupvps-menu21/main/menu.sh -o "$MENU_FILE"
chmod +x "$MENU_FILE"

ln -sf "$MENU_FILE" /usr/bin/menu-bot-backup
echo "[OK] Menu Pro terpasang."

#############################################
# 10. BACKUP PERTAMA
#############################################
echo ""
echo "[INFO] Menjalankan backup pertama..."
timeout 120 bash "$RUNNER" || echo "[WARN] Backup pertama gagal/timout (tidak fatal)."

echo ""
echo "$WATERMARK_END"
echo ""
echo "Ketik: menu-bot-backup"
