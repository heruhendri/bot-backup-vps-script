#!/bin/bash
clear

echo "========================================="
echo "     AUTO BACKUP VPS — TELEGRAM BOT      "
echo "========================================="

# ======================================================
# 1. INPUT
# ======================================================
read -p "Masukkan TOKEN Bot Telegram: " BOT_TOKEN
read -p "Masukkan CHAT_ID Telegram: " CHAT_ID
read -p "Masukkan folder yang mau di-backup (comma separated, contoh: /etc,/var/www): " FOLDERS_RAW

read -p "Backup MySQL? (y/n): " USE_MYSQL
if [[ "$USE_MYSQL" == "y" ]]; then
    read -p "MySQL Host (default: localhost): " MYSQL_HOST
    MYSQL_HOST=${MYSQL_HOST:-localhost}

    read -p "MySQL Username: " MYSQL_USER
    read -s -p "MySQL Password: " MYSQL_PASS
    echo ""
    read -p "Daftar database (comma separated) atau 'all' untuk seluruh DB: " MYSQL_DB_LIST
fi

read -p "Backup PostgreSQL? (y/n): " USE_PG
read -p "Retention (berapa hari file backup disimpan): " RETENTION_DAYS
read -p "Timezone (contoh: Asia/Jakarta): " TZ
read -p "Jadwal cron (format systemd timer, contoh: *-*-* 03:00:00): " CRON_TIME

INSTALL_DIR="/opt/auto-backup"
CONFIG_FILE="$INSTALL_DIR/config.conf"

mkdir -p "$INSTALL_DIR"

# ======================================================
# 2. CREATE CONFIG FILE
# ======================================================
cat <<EOF > "$CONFIG_FILE"
BOT_TOKEN="$BOT_TOKEN"
CHAT_ID="$CHAT_ID"
FOLDERS_RAW="$FOLDERS_RAW"

USE_MYSQL="$USE_MYSQL"
MYSQL_HOST="$MYSQL_HOST"
MYSQL_USER="$MYSQL_USER"
MYSQL_PASS="$MYSQL_PASS"
MYSQL_DB_LIST="$MYSQL_DB_LIST"

USE_PG="$USE_PG"
RETENTION_DAYS="$RETENTION_DAYS"
TZ="$TZ"
INSTALL_DIR="$INSTALL_DIR"
EOF

echo "[OK] Config saved: $CONFIG_FILE"

# ======================================================
# 3. CREATE BACKUP RUNNER
# ======================================================
cat <<'EOF' > "$INSTALL_DIR/backup-runner.sh"
#!/bin/bash
CONFIG_FILE="/opt/auto-backup/config.conf"
source "$CONFIG_FILE"

BACKUP_DIR="$INSTALL_DIR/backups"
mkdir -p "$BACKUP_DIR"

DATE=$(date +%F-%H%M)
FILE="$BACKUP_DIR/backup-$DATE.tar.gz"
TMP_DIR="$INSTALL_DIR/tmp-$DATE"

mkdir -p "$TMP_DIR"

# ----------------------------
#  BACKUP FOLDERS
# ----------------------------
IFS=',' read -r -a FOLDERS <<< "$FOLDERS_RAW"
for f in "${FOLDERS[@]}"; do
    if [ -d "$f" ]; then
        cp -r "$f" "$TMP_DIR/"
    fi
done

# ----------------------------
#  BACKUP MYSQL (MULTI-DB)
# ----------------------------
if [[ "$USE_MYSQL" == "y" ]]; then
    mkdir -p "$TMP_DIR/mysql"

    # GLOBAL MYSQL ARGS
    MYSQL_ARGS="-h$MYSQL_HOST -u$MYSQL_USER -p$MYSQL_PASS"

    if [[ "$MYSQL_DB_LIST" == "all" ]]; then
        echo "[MySQL] Backup ALL databases..."
        mysqldump $MYSQL_ARGS --all-databases > "$TMP_DIR/mysql/all_databases.sql" 2>/dev/null
    else
        IFS=',' read -r -a MYSQL_DBS <<< "$MYSQL_DB_LIST"
        for DB in "${MYSQL_DBS[@]}"; do
            echo "[MySQL] Backup database: $DB"
            mysqldump $MYSQL_ARGS "$DB" > "$TMP_DIR/mysql/$DB.sql" 2>/dev/null
        done
    fi
fi

# ----------------------------
#  BACKUP POSTGRESQL
# ----------------------------
if [[ "$USE_PG" == "y" ]]; then
    mkdir -p "$TMP_DIR/postgres"
    su - postgres -c "pg_dumpall > $TMP_DIR/postgres/all.sql"
fi

# ----------------------------
#  CREATE TAR
# ----------------------------
tar -czf "$FILE" -C "$TMP_DIR" .

# ----------------------------
#  SEND TO TELEGRAM
# ----------------------------
curl -s -F document=@"$FILE" \
     -F caption="Backup selesai: $(basename $FILE)" \
     "https://api.telegram.org/bot$BOT_TOKEN/sendDocument?chat_id=$CHAT_ID"

# ----------------------------
#  AUTO CLEAN TEMP
# ----------------------------
rm -rf "$TMP_DIR"

# ----------------------------
#  RETENTION CLEANER
# ----------------------------
find "$BACKUP_DIR" -type f -mtime +$RETENTION_DAYS -delete
EOF

chmod +x "$INSTALL_DIR/backup-runner.sh"

echo "[OK] Backup runner created."

# ======================================================
# 4. SYSTEMD SERVICE
# ======================================================
cat <<EOF > /etc/systemd/system/auto-backup.service
[Unit]
Description=Auto Backup VPS to Telegram
After=network.target mysql.service mariadb.service postgresql.service

[Service]
Type=oneshot
ExecStart=$INSTALL_DIR/backup-runner.sh
User=root
Environment=TZ=$TZ

[Install]
WantedBy=multi-user.target
EOF

# ======================================================
# 5. SYSTEMD TIMER
# ======================================================
cat <<EOF > /etc/systemd/system/auto-backup.timer
[Unit]
Description=Run Auto Backup VPS

[Timer]
OnCalendar=$CRON_TIME
Persistent=true

[Install]
WantedBy=timers.target
EOF

# ======================================================
# 6. ENABLE SERVICE + TIMER
# ======================================================
systemctl daemon-reload
systemctl enable auto-backup.service
systemctl enable --now auto-backup.timer

echo ""
echo "==========================================="
echo "INSTALL COMPLETE!"
echo "==========================================="
echo "Service  : auto-backup.service"
echo "Timer    : auto-backup.timer"
echo "Config   : $CONFIG_FILE"
echo "Backup   : $INSTALL_DIR/backups"

echo ""
echo "Testing backup pertama..."
bash "$INSTALL_DIR/backup-runner.sh"
echo "Backup pertama dikirim ke Telegram."

echo ""
echo "Menghapus file installer..."
rm -- "$0"
