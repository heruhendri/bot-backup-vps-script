#!/bin/bash

echo "=== Auto Installer Backup to Telegram ==="

# --- Input User ---
read -p "Masukkan folder yang ingin di-backup (contoh: /var/lib/docker/volumes/uptime-kuma/): " FOLDER_BACKUP
read -p "Masukkan Bot Token Telegram: " BOT_TOKEN
read -p "Masukkan Chat ID Telegram: " CHAT_ID
read -p "Masukkan timezone server (contoh: Asia/Jakarta): " TIMEZONE
read -p "Masukkan jam backup (format 24 jam, contoh: 01 untuk jam 01:00): " CRON_HOUR
read -p "Masukkan menit backup (contoh: 00): " CRON_MINUTE
read -p "Hapus backup yang lebih tua dari berapa hari? (contoh: 7): " RETENTION_DAYS

# Validasi folder
if [ ! -d "$FOLDER_BACKUP" ]; then
    echo "Error: Folder '$FOLDER_BACKUP' tidak ditemukan!"
    exit 1
fi

# Set timezone
timedatectl set-timezone "$TIMEZONE"

# Lokasi instalasi
INSTALL_DIR="/opt/auto-backup"
SCRIPT_FILE="$INSTALL_DIR/backup.sh"
CONFIG_FILE="$INSTALL_DIR/config.conf"

mkdir -p $INSTALL_DIR

# Simpan Config
cat <<EOF > $CONFIG_FILE
BOT_TOKEN="$BOT_TOKEN"
CHAT_ID="$CHAT_ID"
FOLDER_BACKUP="$FOLDER_BACKUP"
BACKUP_DIR="/root/backup"
RETENTION_DAYS="$RETENTION_DAYS"
EOF

# Buat Script Backup
cat <<'EOF' > $SCRIPT_FILE
#!/bin/bash
source /opt/auto-backup/config.conf

FILE_NAME="backup-$(date +%F-%H%M).tar.gz"
TARGET="$BACKUP_DIR/$FILE_NAME"

mkdir -p "$BACKUP_DIR"

tar -czf "$TARGET" "$FOLDER_BACKUP"

# Hapus backup lama
find "$BACKUP_DIR" -type f -mtime +$RETENTION_DAYS -name "*.tar.gz" -exec rm -f {} \;

curl -F document=@"$TARGET" \
     -F caption="Backup berhasil: $FILE_NAME" \
     "https://api.telegram.org/bot$BOT_TOKEN/sendDocument?chat_id=$CHAT_ID"
EOF

chmod +x $SCRIPT_FILE

# Pasang Cronjob
(crontab -l 2>/dev/null; echo "$CRON_MINUTE $CRON_HOUR * * * bash $SCRIPT_FILE >/dev/null 2>&1") | crontab -

echo ""
echo "===================================================="
echo "Instalasi selesai!"
echo "Timezone: $TIMEZONE"
echo "Backup dibuat setiap: $CRON_HOUR:$CRON_MINUTE"
echo "Retention: $RETENTION_DAYS hari"
echo "Backup script: $SCRIPT_FILE"
echo "===================================================="

# --- AUTO DELETE INSTALLER ---
INSTALLER_PATH="$(realpath "$0")"
echo "Menghapus file installer: $INSTALLER_PATH"
rm -f "$INSTALLER_PATH"
