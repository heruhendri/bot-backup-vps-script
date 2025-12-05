#!/bin/bash
set -euo pipefail

BASE_DIR="/opt/auto-backup"
CONFIG_FILE="$BASE_DIR/config.conf"

# ------------------------------------------
# Watermark
# ------------------------------------------
echo "==============================================="
echo "        AUTO BACKUP VPS — INSTALLER"
echo "        Script by Hendri"
echo "        Telegram: https://t.me/GbtTapiPngnSndiri"
echo "==============================================="
echo ""

mkdir -p "$BASE_DIR"

# ------------------------------------------
# INPUT CONFIG USER
# ------------------------------------------
if [[ -f "$CONFIG_FILE" ]]; then
    read -p "Config ditemukan. Update config? (y/N): " RESP
    RESP=${RESP:-n}
    if [[ "$RESP" =~ ^[Yy]$ ]]; then UPDATE=1; else UPDATE=0; fi
else
    UPDATE=1
fi

if [[ $UPDATE -eq 1 ]]; then
    read -p "Masukkan BOT TOKEN: " BOT_TOKEN
    read -p "Masukkan CHAT ID: " CHAT_ID
    read -p "Folder to backup (comma separated): " FOLDERS_RAW
    read -p "Backup MySQL? (y/n): " USE_MYSQL
    read -p "Backup MongoDB? (y/n): " USE_MONGO
    read -p "Backup PostgreSQL? (y/n): " USE_PG
    read -p "Retention Days: " RETENTION_DAYS
    read -p "Timezone (ex: Asia/Jakarta): " TZ
    read -p "OnCalendar schedule (*-*-* 03:00:00): " CRON_TIME

    mkdir -p "$BASE_DIR"
    cat > "$CONFIG_FILE" <<EOF
BOT_TOKEN="$BOT_TOKEN"
CHAT_ID="$CHAT_ID"
FOLDERS_RAW="$FOLDERS_RAW"
USE_MYSQL="$USE_MYSQL"
USE_MONGO="$USE_MONGO"
USE_PG="$USE_PG"
RETENTION_DAYS="$RETENTION_DAYS"
TZ="$TZ"
INSTALL_DIR="$BASE_DIR"
EOF

    chmod 600 "$CONFIG_FILE"
fi

# ------------------------------------------
# CALL MODULES
# ------------------------------------------
echo "[OK] Membuat config..."
bash "$BASE_DIR/config/builder.sh"

echo "[OK] Membuat backup runner..."
bash "$BASE_DIR/runner/backup-runner.sh" --build

echo "[OK] Membuat service..."
bash "$BASE_DIR/systemd/service.sh"

echo "[OK] Membuat timer..."
bash "$BASE_DIR/systemd/timer.sh" "$CRON_TIME"

# ------------------------------------------
# INSTALL MENU
# ------------------------------------------
cp "$BASE_DIR/menu/menu.sh" /usr/bin/menu-bot-backup
chmod +x /usr/bin/menu-bot-backup

# ------------------------------------------
# TEST BACKUP
# ------------------------------------------
echo "[INFO] Menjalankan backup pertama..."
bash "$BASE_DIR/runner/backup-runner.sh" || echo "[WARN] Backup pertama gagal"

# ------------------------------------------
# END
# ------------------------------------------
echo ""
echo "==============================================="
echo "  INSTALL COMPLETE — AUTO BACKUP VPS"
echo "==============================================="

rm -- "$0" 2>/dev/null || true
