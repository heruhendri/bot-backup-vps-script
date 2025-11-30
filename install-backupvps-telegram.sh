#!/bin/bash
set -euo pipefail

# Installer: install-auto-backup.sh
# Usage: bash install-auto-backup.sh

echo "=== AUTO INSTALLER: Multi-folder + DB backup -> Telegram + systemd daemon ==="

# --- Input User ---
read -p "Masukkan folder yang ingin dibackup (multiple: pisahkan dengan koma, contoh: /var/lib/docker/volumes/uptime-kuma/,/etc/nginx/): " FOLDERS_RAW
read -p "Apakah Anda ingin backup MySQL/MariaDB? (y/n): " USE_MYSQL
if [[ "${USE_MYSQL,,}" == "y" ]]; then
  read -p "MySQL host (default: localhost): " MYSQL_HOST
  MYSQL_HOST=${MYSQL_HOST:-localhost}
  read -p "MySQL user: " MYSQL_USER
  read -s -p "MySQL password: " MYSQL_PASS
  echo
  read -p "MySQL databases (nama DB pisah koma atau 'all' untuk semua): " MYSQL_DB
fi

read -p "Apakah Anda ingin backup PostgreSQL? (y/n): " USE_PG
if [[ "${USE_PG,,}" == "y" ]]; then
  read -p "Postgres host (default: localhost): " PG_HOST
  PG_HOST=${PG_HOST:-localhost}
  read -p "Postgres user: " PG_USER
  read -s -p "Postgres password: " PG_PASS
  echo
  read -p "Postgres databases (nama DB pisah koma atau 'all' untuk semua): " PG_DB
fi

read -p "Masukkan Bot Token Telegram: " BOT_TOKEN
read -p "Masukkan Chat ID Telegram: " CHAT_ID
read -p "Masukkan timezone server (contoh: Asia/Jakarta) [ENTER untuk skip]: " TIMEZONE_INPUT
read -p "Pilih jenis penjadwalan systemd timer: (1) Harian pada jam:menit  (2) OnCalendar expression (cron-like) => ketik 1 atau 2: " TIMER_CHOICE

if [[ "$TIMER_CHOICE" == "1" ]]; then
  read -p "Masukkan jam (format 24 jam, contoh 01): " SCHED_HOUR
  read -p "Masukkan menit (contoh 00): " SCHED_MINUTE
  # Build systemd OnCalendar like "Daily" at HH:MM => OnCalendar=*-*-* HH:MM:00
  SCHEDULE_ONCAL="*-*-* ${SCHED_HOUR}:${SCHED_MINUTE}:00"
else
  read -p "Masukkan OnCalendar expression (contoh: Mon..Fri *-*-* 03:00:00 atau daily at 01:00 -> *-*-* 01:00:00): " SCHEDULE_ONCAL
fi

read -p "Hapus backup lebih tua dari berapa hari? (contoh: 7): " RETENTION_DAYS

# --- Validate folders ---
IFS=',' read -ra FOLDERS_ARR <<< "$FOLDERS_RAW"
for f in "${FOLDERS_ARR[@]}"; do
  f_trim="$(echo "$f" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  if [ ! -d "$f_trim" ]; then
    echo "Warning: folder '$f_trim' tidak ditemukan. Installer tidak keluar tapi akan dilewati pada backup."
  fi
done

# --- Optional: set timezone ---
if [ -n "$TIMEZONE_INPUT" ]; then
  if command -v timedatectl >/dev/null 2>&1; then
    echo "Mengatur timezone ke: $TIMEZONE_INPUT"
    timedatectl set-timezone "$TIMEZONE_INPUT" || echo "Gagal set timezone (periksa nama zona)"
  else
    echo "timedatectl tidak ditemukan — lewati set timezone."
  fi
fi

# --- Paths ---
INSTALL_DIR="/opt/auto-backup"
BIN_DIR="$INSTALL_DIR/bin"
CONFIG_FILE="$INSTALL_DIR/config.conf"
SCRIPT_FILE="$BIN_DIR/backup-runner.sh"
SYSTEMD_SERVICE="/etc/systemd/system/auto-backup.service"
SYSTEMD_TIMER="/etc/systemd/system/auto-backup.timer"
LOG_FILE="/var/log/auto-backup.log"
mkdir -p "$BIN_DIR"
chown root:root "$INSTALL_DIR" || true

# --- Save config (secure) ---
umask 077
cat > "$CONFIG_FILE" <<EOF
# Auto Backup Config (auto-generated)
/install_dir="$INSTALL_DIR"
BOT_TOKEN="$BOT_TOKEN"
CHAT_ID="$CHAT_ID"
FOLDERS_RAW="$FOLDERS_RAW"
RETENTION_DAYS="$RETENTION_DAYS"
SCHEDULE_ONCAL="$SCHEDULE_ONCAL"
USE_MYSQL="${USE_MYSQL,,}"
USE_PG="${USE_PG,,}"
EOF

# Store DB creds separately with restricted perms if provided
if [[ "${USE_MYSQL,,}" == "y" ]]; then
  cat > "$INSTALL_DIR/mysql.conf" <<EOF
MYSQL_HOST="$MYSQL_HOST"
MYSQL_USER="$MYSQL_USER"
MYSQL_PASS="$MYSQL_PASS"
MYSQL_DB="$MYSQL_DB"
EOF
  chmod 600 "$INSTALL_DIR/mysql.conf"
fi

if [[ "${USE_PG,,}" == "y" ]]; then
  cat > "$INSTALL_DIR/pg.conf" <<EOF
PG_HOST="$PG_HOST"
PG_USER="$PG_USER"
PG_PASS="$PG_PASS"
PG_DB="$PG_DB"
EOF
  chmod 600 "$INSTALL_DIR/pg.conf"
fi
umask 022

# --- Create backup runner script ---
cat > "$SCRIPT_FILE" <<'BASH_SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
CONFIG_FILE="/opt/auto-backup/config.conf"
source "$CONFIG_FILE"
TIMESTAMP="$(date +%F-%H%M%S)"
BACKUP_DIR="/root/backup"
mkdir -p "$BACKUP_DIR"

log() {
  echo "[$(date '+%F %T')] $*" | tee -a /var/log/auto-backup.log
}

send_telegram() {
  local text="$1"
  local file_path="${2:-}"
  if [ -n "$file_path" ] && [ -f "$file_path" ]; then
    curl -s -F document=@"$file_path" -F caption="$text" "https://api.telegram.org/bot$BOT_TOKEN/sendDocument?chat_id=$CHAT_ID" >/dev/null || true
  else
    # send message only
    curl -s -X POST "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" -d chat_id="$CHAT_ID" -d text="$text" >/dev/null || true
  fi
}

log "=== Backup started: $TIMESTAMP ==="
send_telegram "Backup started: $TIMESTAMP"

ARCH_NAME="backup-${TIMESTAMP}.tar.gz"
ARCH_PATH="$BACKUP_DIR/$ARCH_NAME"

# prepare temp dir for DB dumps
TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# 1) Dump MySQL if enabled
if [[ "${USE_MYSQL}" == "y" ]] || [[ "${USE_MYSQL}" == "Y" ]]; then
  if command -v mysqldump >/dev/null 2>&1; then
    source /opt/auto-backup/mysql.conf
    log "Starting MySQL dump..."
    if [ "$MYSQL_DB" == "all" ]; then
      mysqldump --single-transaction --routines --events -h "$MYSQL_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASS" --all-databases > "$TMP_DIR/mysql-all-${TIMESTAMP}.sql" || { log "MySQL dump failed"; send_telegram "MySQL dump failed: $TIMESTAMP"; }
    else
      IFS=',' read -ra DBS <<< "$MYSQL_DB"
      for db in "${DBS[@]}"; do
        db_trim="$(echo "$db" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        mysqldump --single-transaction --routines --events -h "$MYSQL_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASS" "$db_trim" > "$TMP_DIR/mysql-${db_trim}-${TIMESTAMP}.sql" || { log "MySQL dump failed for $db_trim"; send_telegram "MySQL dump failed for $db_trim: $TIMESTAMP"; }
      done
    fi
  else
    log "mysqldump tidak ditemukan — lewati MySQL."
    send_telegram "mysqldump not found on server — skipped MySQL."
  fi
fi

# 2) Dump Postgres if enabled
if [[ "${USE_PG}" == "y" ]] || [[ "${USE_PG}" == "Y" ]]; then
  if command -v pg_dumpall >/dev/null 2>&1 || command -v pg_dump >/dev/null 2>&1; then
    source /opt/auto-backup/pg.conf
    export PGPASSWORD="$PG_PASS"
    log "Starting Postgres dump..."
    if [ "$PG_DB" == "all" ]; then
      pg_dumpall -h "$PG_HOST" -U "$PG_USER" > "$TMP_DIR/postgres-all-${TIMESTAMP}.sql" || { log "Postgres dump failed"; send_telegram "Postgres dump failed: $TIMESTAMP"; }
    else
      IFS=',' read -ra PDBS <<< "$PG_DB"
      for pdb in "${PDBS[@]}"; do
        pdb_trim="$(echo "$pdb" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        pg_dump -h "$PG_HOST" -U "$PG_USER" -d "$pdb_trim" -F p -f "$TMP_DIR/postgres-${pdb_trim}-${TIMESTAMP}.sql" || { log "Postgres dump failed for $pdb_trim"; send_telegram "Postgres dump failed for $pdb_trim: $TIMESTAMP"; }
      done
    fi
    unset PGPASSWORD
  else
    log "pg_dump/pg_dumpall tidak ditemukan — lewati Postgres."
    send_telegram "pg_dump not found on server — skipped Postgres."
  fi
fi

# 3) Archive folders + DB dumps
# Build list of sources
TAR_SOURCES=()
IFS=',' read -ra FOLDERS <<< "$FOLDERS_RAW"
for f in "${FOLDERS[@]}"; do
  f_trim="$(echo "$f" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  if [ -d "$f_trim" ]; then
    TAR_SOURCES+=("$f_trim")
  else
    log "Skip missing: $f_trim"
  fi
done

# include tmp DB dumps
if [ -d "$TMP_DIR" ]; then
  # collect any .sql files
  SQLFILES=( "$TMP_DIR"/*.sql )
  if [ -e "${SQLFILES[0]:-}" ]; then
    TAR_SOURCES+=( "$TMP_DIR" )
  fi
fi

if [ ${#TAR_SOURCES[@]} -eq 0 ]; then
  log "Tidak ada sumber untuk di-archive. Exit with error."
  send_telegram "Backup failed: no sources found to archive ($TIMESTAMP)"
  exit 1
fi

# create archive
log "Membuat archive: $ARCH_PATH"
tar -czf "$ARCH_PATH" "${TAR_SOURCES[@]}" || { log "Tar failed"; send_telegram "Tar failed: $TIMESTAMP"; exit 1; }

# 4) Retention: hapus file lebih tua dari RETENTION_DAYS
log "Menghapus backup lebih tua dari $RETENTION_DAYS hari"
find "$BACKUP_DIR" -type f -name "backup-*.tar.gz" -mtime +$RETENTION_DAYS -exec rm -f {} \; || true

# 5) Send to Telegram
log "Kirim backup ke Telegram: $ARCH_PATH"
send_telegram "Backup berhasil: $ARCH_NAME" "$ARCH_PATH"

log "=== Backup finished: $TIMESTAMP ==="
send_telegram "Backup finished: $TIMESTAMP"

exit 0
BASH_SCRIPT

chmod +x "$SCRIPT_FILE"
chown root:root "$SCRIPT_FILE"

# --- Create systemd service ---
cat > "$SYSTEMD_SERVICE" <<EOF
[Unit]
Description=Auto Backup Service (runs archive & db dumps)
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=$SCRIPT_FILE
StandardOutput=journal
StandardError=journal
EOF

# --- Create systemd timer ---
cat > "$SYSTEMD_TIMER" <<EOF
[Unit]
Description=Timer for Auto Backup Service

[Timer]
OnCalendar=$SCHEDULE_ONCAL
Persistent=true

[Install]
WantedBy=timers.target
EOF

# --- Reload systemd and enable/start timer ---
systemctl daemon-reload
systemctl enable --now auto-backup.timer
systemctl start auto-backup.timer || true

# Initialize log file
touch "$LOG_FILE"
chmod 644 "$LOG_FILE"

echo "===================================================="
echo "Instalasi selesai!"
echo "Service: auto-backup.service"
echo "Timer:   auto-backup.timer (OnCalendar = $SCHEDULE_ONCAL)"
echo "Script runner: $SCRIPT_FILE"
echo "Config file: $CONFIG_FILE"
echo "Backup folder: /root/backup"
echo "Log file: $LOG_FILE (also available via journalctl -u auto-backup.service)"
echo "Retention (days): $RETENTION_DAYS"
echo "Untuk menjalankan manual: sudo systemctl start auto-backup.service"
echo "Untuk melihat timer status: systemctl list-timers --all | grep auto-backup"
echo "===================================================="

# --- Self-delete installer (optional) ---
INSTALLER_PATH="$(realpath "$0")"
echo "Menghapus file installer: $INSTALLER_PATH"
rm -f "$INSTALLER_PATH" || true

# End
