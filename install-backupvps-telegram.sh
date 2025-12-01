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

# ======================================================
#  MYSQL MULTI CONFIG INPUT
# ======================================================
read -p "Backup MySQL? (y/n): " USE_MYSQL
MYSQL_MULTI_CONF=""
if [[ "$USE_MYSQL" == "y" ]]; then
    echo ""
    read -p "Berapa konfigurasi MySQL yang ingin Anda tambahkan? " MYSQL_COUNT
    
    for ((i=1; i<=MYSQL_COUNT; i++)); do
        echo ""
        echo "📌 Konfigurasi MySQL ke-$i"
        
        read -p "MySQL Host (default: localhost): " MYSQL_HOST
        MYSQL_HOST=${MYSQL_HOST:-localhost}

        read -p "MySQL Username: " MYSQL_USER
        read -s -p "MySQL Password: " MYSQL_PASS
        echo ""

        echo "Mode backup database:"
        echo "1) Backup SEMUA database"
        echo "2) Pilih database tertentu"
        read -p "Pilih (1/2): " MODE

        if [[ "$MODE" == "1" ]]; then
            DBLIST="all"
        else
            read -p "Masukkan daftar DB (comma separated, ex: db1,db2): " DBLIST
        fi

        ENTRY="${MYSQL_USER}:${MYSQL_PASS}@${MYSQL_HOST}:${DBLIST}"

        if [[ -z "$MYSQL_MULTI_CONF" ]]; then
            MYSQL_MULTI_CONF="$ENTRY"
        else
            MYSQL_MULTI_CONF="${MYSQL_MULTI_CONF};${ENTRY}"
        fi
    done
fi

# ======================================================
#  POSTGRES INPUT
# ======================================================
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
MYSQL_MULTI_CONF="$MYSQL_MULTI_CONF"

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
#  BACKUP MYSQL MULTI CONFIG
# ----------------------------
if [[ "$USE_MYSQL" == "y" ]]; then
    mkdir -p "$TMP_DIR/mysql"

    IFS=';' read -r -a MYSQL_ITEMS <<< "$MYSQL_MULTI_CONF"

    for ITEM in "${MYSQL_ITEMS[@]}"; do
        # Format: user:pass@host:db1,db2
        USERPASS=$(echo "$ITEM" | cut -d'@' -f1)
        HOSTDB=$(echo "$ITEM" | cut -d'@' -f2)

        MYSQL_USER=$(echo "$USERPASS" | cut -d':' -f1)
        MYSQL_PASS=$(echo "$USERPASS" | cut -d':' -f2)

        MYSQL_HOST=$(echo "$HOSTDB" | cut -d':' -f1)
        MYSQL_DB_LIST=$(echo "$HOSTDB" | cut -d':' -f2)

        MYSQL_ARGS="-h$MYSQL_HOST -u$MYSQL_USER -p$MYSQL_PASS"

        # backup semua DB
        if [[ "$MYSQL_DB_LIST" == "all" ]]; then
            OUTFILE="$TMP_DIR/mysql/${MYSQL_USER}@${MYSQL_HOST}_ALL.sql"
            echo "[MySQL] Backup ALL DB -> $OUTFILE"
            mysqldump $MYSQL_ARGS --all-databases > "$OUTFILE" 2>/dev/null
        else
            # backup masing-masing DB
            IFS=',' read -r -a DBARR <<< "$MYSQL_DB_LIST"
            for DB in "${DBARR[@]}"; do
                OUTFILE="$TMP_DIR/mysql/${MYSQL_USER}@${MYSQL_HOST}_${DB}.sql"
                echo "[MySQL] Backup DB $DB -> $OUTFILE"
                mysqldump $MYSQL_ARGS "$DB" > "$OUTFILE" 2>/dev/null
            done
        fi
    done
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
