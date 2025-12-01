#!/bin/bash
# Auto Backup VPS — Installer + CLI Menu (single-file)
# Save as: install-auto-backup.sh
# Run as root
set -euo pipefail
IFS=$'\n\t'

INSTALL_DIR="/opt/auto-backup"
CONFIG_FILE="$INSTALL_DIR/config.conf"
RUNNER="$INSTALL_DIR/backup-runner.sh"
SERVICE_FILE="/etc/systemd/system/auto-backup.service"
TIMER_FILE="/etc/systemd/system/auto-backup.timer"
MENU_BIN="/usr/local/bin/menu-bot-backup"
LOGFILE="$INSTALL_DIR/menu-pro.log"

# -------------------------
# Helper functions
# -------------------------
confirm() {
    local msg="$1"
    read -p "$msg (y/N): " ans
    case "$ans" in
        y|Y) return 0 ;;
        *) return 1 ;;
    esac
}

ensure_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        echo "Jalankan script ini sebagai root!"
        exit 1
    fi
}

# -------------------------
# Installer interactive
# -------------------------
installer() {
    mkdir -p "$INSTALL_DIR"
    echo "========================================="
    echo "     AUTO BACKUP VPS — TELEGRAM BOT      "
    echo "========================================="
    read -p "Masukkan TOKEN Bot Telegram: " BOT_TOKEN
    read -p "Masukkan CHAT_ID Telegram: " CHAT_ID
    read -p "Masukkan folder yang mau di-backup (comma separated, contoh: /etc,/var/www): " FOLDERS_RAW

    read -p "Backup MySQL? (y/n): " USE_MYSQL
    MYSQL_MULTI_CONF=""
    if [[ "$USE_MYSQL" == "y" ]]; then
        echo ""
        read -p "Berapa konfigurasi MySQL yang ingin Anda tambahkan? " MYSQL_COUNT
        for ((i=1; i<=MYSQL_COUNT; i++)); do
            echo ""
            echo "Konfigurasi MySQL ke-$i"
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

    read -p "Backup PostgreSQL? (y/n): " USE_PG
    read -p "Retention (berapa hari file backup disimpan): " RETENTION_DAYS
    read -p "Timezone (contoh: Asia/Jakarta): " TZ
    read -p "Jadwal cron (format systemd OnCalendar, contoh: *-*-* 03:00:00): " CRON_TIME

    # create config
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
EOF

    echo "[OK] Config saved: $CONFIG_FILE"
    timedatectl set-timezone "$TZ" || true

    # create runner
    cat > "$RUNNER" <<'EOF'
#!/bin/bash
CONFIG_FILE="/opt/auto-backup/config.conf"
source "$CONFIG_FILE"
export TZ="$TZ"

BACKUP_DIR="$INSTALL_DIR/backups"
mkdir -p "$BACKUP_DIR"

DATE=$(date +%F-%H%M%S)
FILE="$BACKUP_DIR/backup-$DATE.tar.gz"
TMP_DIR="$INSTALL_DIR/tmp-$DATE"

mkdir -p "$TMP_DIR"

# backup folders
IFS=',' read -r -a FOLDERS <<< "$FOLDERS_RAW"
for f in "${FOLDERS[@]}"; do
    if [ -d "$f" ]; then
        # preserve attributes & links
        cp -a "$f" "$TMP_DIR/" 2>/dev/null || true
    fi
done

# backup mysql (multi)
if [[ "$USE_MYSQL" == "y" && ! -z "$MYSQL_MULTI_CONF" ]]; then
    mkdir -p "$TMP_DIR/mysql"
    IFS=';' read -r -a MYSQL_ITEMS <<< "$MYSQL_MULTI_CONF"
    for ITEM in "${MYSQL_ITEMS[@]}"; do
        USERPASS=$(echo "$ITEM" | cut -d'@' -f1)
        HOSTDB=$(echo "$ITEM" | cut -d'@' -f2)
        MYSQL_USER=$(echo "$USERPASS" | cut -d':' -f1)
        MYSQL_PASS=$(echo "$USERPASS" | cut -d':' -f2)
        MYSQL_HOST=$(echo "$HOSTDB" | cut -d':' -f1)
        MYSQL_DB_LIST=$(echo "$HOSTDB" | cut -d':' -f2)
        MYSQL_ARGS="-h$MYSQL_HOST -u$MYSQL_USER -p$MYSQL_PASS"
        if [[ "$MYSQL_DB_LIST" == "all" ]]; then
            OUTFILE="$TMP_DIR/mysql/${MYSQL_USER}@${MYSQL_HOST}_ALL.sql"
            mysqldump $MYSQL_ARGS --all-databases > "$OUTFILE" 2>/dev/null || true
        else
            IFS=',' read -r -a DBARR <<< "$MYSQL_DB_LIST"
            for DB in "${DBARR[@]}"; do
                OUTFILE="$TMP_DIR/mysql/${MYSQL_USER}@${MYSQL_HOST}_${DB}.sql"
                mysqldump $MYSQL_ARGS "$DB" > "$OUTFILE" 2>/dev/null || true
            done
        fi
    done
fi

# backup postgres
if [[ "$USE_PG" == "y" ]]; then
    mkdir -p "$TMP_DIR/postgres"
    if id -u postgres >/dev/null 2>&1; then
        su - postgres -c "pg_dumpall > $TMP_DIR/postgres/all.sql" 2>/dev/null || true
    else
        pg_dumpall > "$TMP_DIR/postgres/all.sql" 2>/dev/null || true
    fi
fi

tar -czf "$FILE" -C "$TMP_DIR" . 2>/dev/null || true

# log to syslog for easy detection
logger -t auto-backup "Backup selesai: $(basename "$FILE")"

# send to telegram (best effort)
if [[ -n "$BOT_TOKEN" && -n "$CHAT_ID" && -f "$FILE" ]]; then
    curl -s -F document=@"$FILE" -F caption="Backup selesai: $(basename $FILE)" "https://api.telegram.org/bot$BOT_TOKEN/sendDocument?chat_id=$CHAT_ID" >/dev/null 2>&1 || true
fi

rm -rf "$TMP_DIR"
find "$BACKUP_DIR" -type f -mtime +"$RETENTION_DAYS" -delete 2>/dev/null || true
EOF

    chmod +x "$RUNNER"
    echo "[OK] Backup runner created: $RUNNER"

    # systemd unit
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Auto Backup VPS to Telegram
After=network.target mysql.service mariadb.service postgresql.service

[Service]
Type=oneshot
Environment="TZ=$TZ"
ExecStart=/usr/bin/env TZ=$TZ $RUNNER
User=root

[Install]
WantedBy=multi-user.target
EOF

    # timer
    cat > "$TIMER_FILE" <<EOF
[Unit]
Description=Run Auto Backup VPS

[Timer]
OnCalendar=$CRON_TIME
Persistent=true

[Install]
WantedBy=timers.target
EOF

    systemctl daemon-reload
    systemctl enable --now auto-backup.timer || true
    systemctl enable auto-backup.service || true

    # create menu binary
    cat > "$MENU_BIN" <<'EOF'
#!/bin/bash
# menu-bot-backup - launcher for the interactive menu stored in /opt/auto-backup/menu.sh
if [[ -x /opt/auto-backup/menu.sh ]]; then
    exec /opt/auto-backup/menu.sh
else
    echo "Menu belum terpasang. Jalankan installer lagi atau perbaiki /opt/auto-backup/menu.sh"
    exit 1
fi
EOF

    chmod +x "$MENU_BIN"
    echo "[OK] menu-bot-backup command created at $MENU_BIN"

    # prepare initial menu script
    cat > "$INSTALL_DIR/menu.sh" <<'EOF'
#!/bin/bash
# CLI Menu for Auto Backup — /opt/auto-backup/menu.sh
CONFIG="/opt/auto-backup/config.conf"
INSTALL_DIR="/opt/auto-backup"
RUNNER="$INSTALL_DIR/backup-runner.sh"
SERVICE="auto-backup.service"
TIMER="auto-backup.timer"
LOG="$INSTALL_DIR/menu-pro.log"

source "$CONFIG"

save_config() {
    cat > "$CONFIG" <<EOC
BOT_TOKEN="$BOT_TOKEN"
CHAT_ID="$CHAT_ID"
FOLDERS_RAW="$FOLDERS_RAW"

USE_MYSQL="$USE_MYSQL"
MYSQL_MULTI_CONF="$MYSQL_MULTI_CONF"

USE_PG="$USE_PG"
RETENTION_DAYS="$RETENTION_DAYS"
TZ="$TZ"
INSTALL_DIR="$INSTALL_DIR"
EOC
    echo "[$(date '+%F %T')] Config saved." >> "$LOG"
}

pause() { read -p "Tekan ENTER untuk lanjut..."; }

show_status() {
    echo "====== SERVICE STATUS ======"
    systemctl --no-pager status $SERVICE | sed -n '1,6p'
    echo ""
    echo "Active state: $(systemctl is-active $SERVICE || echo inactive)"
    echo "Enabled: $(systemctl is-enabled $SERVICE 2>/dev/null || echo disabled)"
    echo ""
    # last backup via syslog / latest file
    echo "------ Last backups (by file) ------"
    mkdir -p "$INSTALL_DIR/backups"
    LASTFILE=$(ls -1t "$INSTALL_DIR/backups" 2>/dev/null | head -n1 || true)
    if [[ -n "$LASTFILE" ]]; then
        echo "Last backup file : $LASTFILE"
        stat --printf="File mtime: %y\nSize: %s bytes\n" "$INSTALL_DIR/backups/$LASTFILE" 2>/dev/null || true
    else
        echo "(tidak ada file backup)"
    fi
    echo ""
    # last backup via journal (logger tag auto-backup)
    echo "------ Last backup (journal) ------"
    journalctl -t auto-backup -n 5 --no-pager || echo "(tidak ada entry journal)"
    echo ""
    # next scheduled timer
    echo "------ Next scheduled run (timer) ------"
    systemctl list-timers --all --no-legend | awk '/auto-backup.timer/ {print "Next: "$1" "$2" "$3" "$4" "$5" "$6" "$7; found=1} END { if (!found) print "(tidak ditemukan timer aktif)"}'
    echo "================================="
}

list_backups() {
    echo "Daftar file backup:"
    ls -1tr "$INSTALL_DIR/backups" 2>/dev/null || echo "(tidak ada file backup)"
}

test_backup() {
    echo "Menjalankan backup-runner (test)..."
    bash "$RUNNER"
    echo "Selesai. Periksa Telegram / $INSTALL_DIR/backups"
}

add_folder() {
    read -p "Masukkan folder baru (single path, atau comma separated): " NEW_FOLDER
    if [[ -z "$NEW_FOLDER" ]]; then echo "Tidak ada input."; return; fi
    if [[ -z "$FOLDERS_RAW" ]]; then FOLDERS_RAW="$NEW_FOLDER"; else FOLDERS_RAW="$FOLDERS_RAW,$NEW_FOLDER"; fi
    echo "[OK] Folder tambahan disiapkan."
}

delete_folder() {
    if [[ -z "$FOLDERS_RAW" ]]; then echo "Tidak ada folder yang bisa dihapus."; return; fi
    IFS=',' read -ra FL <<< "$FOLDERS_RAW"
    echo "Daftar folder:"
    for i in "${!FL[@]}"; do printf "%2d) %s\n" $((i+1)) "${FL[$i]}"; done
    read -p "Masukkan nomor yang ingin dihapus: " NUM
    if ! [[ "$NUM" =~ ^[0-9]+$ ]] || (( NUM < 1 || NUM > ${#FL[@]} )); then echo "Pilihan tidak valid."; return; fi
    unset 'FL[NUM-1]'
    FOLDERS_RAW=$(IFS=','; echo "${FL[*]}")
    echo "[OK] Folder dihapus."
}

list_mysql() {
    if [[ -z "$MYSQL_MULTI_CONF" ]]; then echo "(tidak ada konfigurasi MySQL)"; return; fi
    IFS=';' read -ra LIST <<< "$MYSQL_MULTI_CONF"
    i=1
    for item in "${LIST[@]}"; do echo "[$i] $item"; ((i++)); done
}

add_mysql() {
    echo "Tambah konfigurasi MySQL baru:"
    read -p "MySQL Host (default: localhost): " MYSQL_HOST
    MYSQL_HOST=${MYSQL_HOST:-localhost}
    read -p "MySQL Username: " MYSQL_USER
    read -s -p "MySQL Password: " MYSQL_PASS; echo ""
    echo "Mode database: 1) Semua  2) Pilih"
    read -p "Pilih: " MODE
    if [[ "$MODE" == "1" ]]; then DB="all"; else read -p "Masukkan nama database (comma separated): " DB; fi
    NEW_ENTRY="${MYSQL_USER}:${MYSQL_PASS}@${MYSQL_HOST}:${DB}"
    if [[ -z "$MYSQL_MULTI_CONF" ]]; then MYSQL_MULTI_CONF="$NEW_ENTRY"; else MYSQL_MULTI_CONF="$MYSQL_MULTI_CONF;$NEW_ENTRY"; fi
    echo "[OK] Ditambahkan."
}

edit_mysql() {
    if [[ -z "$MYSQL_MULTI_CONF" ]]; then echo "Tidak ada konfigurasi MySQL."; return; fi
    IFS=';' read -ra LIST <<< "$MYSQL_MULTI_CONF"
    for i in "${!LIST[@]}"; do printf "%2d) %s\n" $((i+1)) "${LIST[$i]}"; done
    read -p "Pilih nomor untuk diedit: " NUM
    if ! [[ "$NUM" =~ ^[0-9]+$ ]] || (( NUM < 1 || NUM > ${#LIST[@]} )); then echo "Pilihan invalid."; return; fi
    IDX=$((NUM-1))
    OLD="${LIST[$IDX]}"
    OLD_USER=$(echo "$OLD" | cut -d':' -f1)
    OLD_PASS=$(echo "$OLD" | cut -d':' -f2 | cut -d'@' -f1)
    OLD_HOST=$(echo "$OLD" | cut -d'@' -f2 | cut -d':' -f1)
    OLD_DB=$(echo "$OLD" | rev | cut -d: -f1 | rev)
    read -p "MySQL Host [$OLD_HOST]: " MYSQL_HOST; MYSQL_HOST=${MYSQL_HOST:-$OLD_HOST}
    read -p "MySQL Username [$OLD_USER]: " MYSQL_USER; MYSQL_USER=${MYSQL_USER:-$OLD_USER}
    read -s -p "MySQL Password (kosong = tetap): " MYSQL_PASS; echo ""
    if [[ -z "$MYSQL_PASS" ]]; then MYSQL_PASS="$OLD_PASS"; fi
    read -p "Database (comma or 'all') [$OLD_DB]: " DB; DB=${DB:-$OLD_DB}
    NEW_ENTRY="${MYSQL_USER}:${MYSQL_PASS}@${MYSQL_HOST}:${DB}"
    LIST[$IDX]="$NEW_ENTRY"
    MYSQL_MULTI_CONF=$(IFS=';'; echo "${LIST[*]}")
    echo "[OK] Konfigurasi diperbarui."
}

delete_mysql() {
    if [[ -z "$MYSQL_MULTI_CONF" ]]; then echo "Tidak ada konfigurasi MySQL."; return; fi
    IFS=';' read -ra LIST <<< "$MYSQL_MULTI_CONF"
    for i in "${!LIST[@]}"; do printf "%2d) %s\n" $((i+1)) "${LIST[$i]}"; done
    read -p "Pilih nomor yang ingin dihapus: " NUM
    if ! [[ "$NUM" =~ ^[0-9]+$ ]] || (( NUM < 1 || NUM > ${#LIST[@]} )); then echo "Pilihan invalid."; return; fi
    unset 'LIST[NUM-1]'
    MYSQL_MULTI_CONF=$(IFS=';'; echo "${LIST[*]}")
    echo "[OK] Dihapus."
}

edit_pg() {
    read -p "Backup PostgreSQL? (y/n) [current: $USE_PG]: " x
    if [[ ! -z "$x" ]]; then USE_PG="$x"; fi
    echo "[OK] USE_PG set ke $USE_PG"
    read -p "Tekan ENTER jika ingin melakukan test dump sekarang, atau CTRL+C untuk batal..."
    if [[ "$USE_PG" == "y" ]]; then
        TMP="$INSTALL_DIR/pg_test_$(date +%s).sql"
        if su - postgres -c "pg_dumpall > $TMP" 2>/dev/null; then
            echo "Test pg_dumpall berhasil: $TMP"
        else
            echo "pg_dumpall gagal. Pastikan user 'postgres' ada dan pg_dumpall terinstall."
            rm -f "$TMP"
        fi
    else
        echo "PG backup dinonaktifkan."
    fi
}

restore_backup() {
    echo "Daftar file backup (urut waktu):"
    files=()
    while IFS= read -r -d $'\0' f; do files+=("$f"); done < <(find "$INSTALL_DIR/backups" -maxdepth 1 -type f -print0 | sort -z)
    if (( ${#files[@]} == 0 )); then echo "Tidak ada file backup." ; return; fi
    for i in "${!files[@]}"; do printf "%2d) %s\n" $((i+1)) "$(basename "${files[$i]}")"; done
    read -p "Pilih nomor file untuk restore: " NUM
    if ! [[ "$NUM" =~ ^[0-9]+$ ]] || (( NUM < 1 || NUM > ${#files[@]} )); then echo "Pilihan invalid."; return; fi
    SELECT="${files[$((NUM-1))]}"
    echo "File dipilih: $SELECT"
    tar -tzf "$SELECT" | sed -n '1,30p'
    read -p "Lanjut restore dan timpa file sesuai archive ke root (/)? (y/N): " ans
    if [[ "$ans" != "y" && "$ans" != "Y" ]]; then echo "Restore dibatalkan."; return; fi
    TMPREST="$INSTALL_DIR/restore_tmp_$(date +%s)"
    mkdir -p "$TMPREST"
    tar -xzf "$SELECT" -C "$TMPREST"
    echo "File diekstrak ke $TMPREST"
    read -p "Ekstrak ke / (akan menimpa file yang ada). Lanjut? (y/N): " ans2
    if [[ "$ans2" == "y" || "$ans2" == "Y" ]]; then
        rsync -a --delete "$TMPREST"/ /
        echo "[OK] Restore selesai."
        echo "[$(date '+%F %T')] Restore from $(basename "$SELECT")" >> "$LOG"
    else
        echo "Restore dibatalkan."
    fi
    rm -rf "$TMPREST"
}

rebuild_installer_files() {
    echo "Membangun ulang service, timer, dan backup-runner berdasarkan config..."
    # rebuild runner, service, timer using content of this script's RUNNER/SERVICE/TIMER templates
    # For simplicity: rewrite runner by invoking the main installer's re-create logic (we assume config loaded)
    cat > "$RUNNER" <<'RNR'
#!/bin/bash
CONFIG_FILE="/opt/auto-backup/config.conf"
source "$CONFIG_FILE"
export TZ="$TZ"
BACKUP_DIR="$INSTALL_DIR/backups"
mkdir -p "$BACKUP_DIR"
DATE=$(date +%F-%H%M%S)
FILE="$BACKUP_DIR/backup-$DATE.tar.gz"
TMP_DIR="$INSTALL_DIR/tmp-$DATE"
mkdir -p "$TMP_DIR"
IFS=',' read -r -a FOLDERS <<< "$FOLDERS_RAW"
for f in "${FOLDERS[@]}"; do
    if [ -d "$f" ]; then cp -a "$f" "$TMP_DIR/" 2>/dev/null || true; fi
done
if [[ "$USE_MYSQL" == "y" && ! -z "$MYSQL_MULTI_CONF" ]]; then
    mkdir -p "$TMP_DIR/mysql"
    IFS=';' read -r -a MYSQL_ITEMS <<< "$MYSQL_MULTI_CONF"
    for ITEM in "${MYSQL_ITEMS[@]}"; do
        USERPASS=$(echo "$ITEM" | cut -d'@' -f1)
        HOSTDB=$(echo "$ITEM" | cut -d'@' -f2)
        MYSQL_USER=$(echo "$USERPASS" | cut -d':' -f1)
        MYSQL_PASS=$(echo "$USERPASS" | cut -d':' -f2)
        MYSQL_HOST=$(echo "$HOSTDB" | cut -d':' -f1)
        MYSQL_DB_LIST=$(echo "$HOSTDB" | cut -d':' -f2)
        MYSQL_ARGS="-h$MYSQL_HOST -u$MYSQL_USER -p$MYSQL_PASS"
        if [[ "$MYSQL_DB_LIST" == "all" ]]; then
            OUTFILE="$TMP_DIR/mysql/${MYSQL_USER}@${MYSQL_HOST}_ALL.sql"
            mysqldump $MYSQL_ARGS --all-databases > "$OUTFILE" 2>/dev/null || true
        else
            IFS=',' read -r -a DBARR <<< "$MYSQL_DB_LIST"
            for DB in "${DBARR[@]}"; do
                OUTFILE="$TMP_DIR/mysql/${MYSQL_USER}@${MYSQL_HOST}_${DB}.sql"
                mysqldump $MYSQL_ARGS "$DB" > "$OUTFILE" 2>/dev/null || true
            done
        fi
    done
fi
if [[ "$USE_PG" == "y" ]]; then
    mkdir -p "$TMP_DIR/postgres"
    if id -u postgres >/dev/null 2>&1; then su - postgres -c "pg_dumpall > $TMP_DIR/postgres/all.sql" 2>/dev/null || true
    else pg_dumpall > "$TMP_DIR/postgres/all.sql" 2>/dev/null || true; fi
fi
tar -czf "$FILE" -C "$TMP_DIR" . 2>/dev/null || true
logger -t auto-backup "Backup selesai: $(basename "$FILE")"
if [[ -n "$BOT_TOKEN" && -n "$CHAT_ID" && -f "$FILE" ]]; then
    curl -s -F document=@"$FILE" -F caption="Backup selesai: $(basename $FILE)" "https://api.telegram.org/bot$BOT_TOKEN/sendDocument?chat_id=$CHAT_ID" >/dev/null 2>&1 || true
fi
rm -rf "$TMP_DIR"
find "$BACKUP_DIR" -type f -mtime +"$RETENTION_DAYS" -delete 2>/dev/null || true
RNR
    chmod +x "$RUNNER"
    cat > "/etc/systemd/system/auto-backup.service" <<EOT
[Unit]
Description=Auto Backup VPS to Telegram
After=network.target mysql.service mariadb.service postgresql.service
[Service]
Type=oneshot
Environment="TZ=$TZ"
ExecStart=/usr/bin/env TZ=$TZ $RUNNER
User=root
[Install]
WantedBy=multi-user.target
EOT
    # preserve existing OnCalendar if present
    CURRENT_ONCAL="*-*-* 03:00:00"
    if [[ -f "/etc/systemd/system/auto-backup.timer" ]]; then
        oc=$(grep -E '^OnCalendar=' /etc/systemd/system/auto-backup.timer 2>/dev/null | head -n1 | cut -d'=' -f2-)
        if [[ -n "$oc" ]]; then CURRENT_ONCAL="$oc"; fi
    fi
    cat > "/etc/systemd/system/auto-backup.timer" <<EOT
[Unit]
Description=Run Auto Backup VPS
[Timer]
OnCalendar=$CURRENT_ONCAL
Persistent=true
[Install]
WantedBy=timers.target
EOT
    systemctl daemon-reload
    systemctl enable --now auto-backup.timer || true
    systemctl enable auto-backup.service || true
    echo "[OK] Rebuilt service/timer/runner." | tee -a "$LOG"
}

encrypt_last_backup() {
    mkdir -p "$INSTALL_DIR/backups"
    LAST=$(ls -1t "$INSTALL_DIR/backups" 2>/dev/null | head -n1)
    if [[ -z "$LAST" ]]; then echo "Tidak ada backup untuk diencrypt."; return; fi
    read -s -p "Masukkan password enkripsi (akan digunakan untuk zip): " PWD; echo ""
    OUT="$INSTALL_DIR/backups/${LAST%.*}.zip"
    if command -v zip >/dev/null 2>&1; then
        zip -P "$PWD" "$OUT" "$INSTALL_DIR/backups/$LAST" >/dev/null 2>&1
        echo "Encrypted archive dibuat: $OUT"
    else
        echo "Perintah zip tidak tersedia. Install zip lalu ulangi."
    fi
}

build_oncalendar() {
    echo "Bentuk OnCalendar bisa: '*-*-* HH:MM:SS' (setiap hari jam tertentu)"
    read -p "Masukkan string OnCalendar yang diinginkan: " OC
    if [[ -z "$OC" ]]; then echo "Tidak ada input."; return; fi
    sed -i "s|OnCalendar=.*|OnCalendar=$OC|g" "/etc/systemd/system/auto-backup.timer"
    systemctl daemon-reload
    systemctl restart auto-backup.timer
    echo "[OK] OnCalendar disimpan."
}

show_config_file() {
    echo "================ CONFIG FILE ================"
    cat "$CONFIG"
    echo "============================================"
}

reload_systemd() {
    systemctl daemon-reload
    systemctl restart auto-backup.timer 2>/dev/null || true
    systemctl restart auto-backup.service 2>/dev/null || true
    echo "[OK] Systemd reloaded & services restarted."
}

# main loop
while true; do
    clear
    echo "=============================================="
    echo "   AUTO BACKUP — MENU PRO (Telegram VPS)"
    echo "=============================================="
    echo "1) Lihat status service / jadwal / last backup"
    echo "2) Lihat konfigurasi"
    echo "3) Edit BOT TOKEN"
    echo "4) Edit CHAT ID"
    echo "5) Tambah folder backup"
    echo "6) Hapus folder backup"
    echo "7) Tambah konfigurasi MySQL"
    echo "8) Edit konfigurasi MySQL"
    echo "9) Hapus konfigurasi MySQL"
    echo "10) Edit PostgreSQL settings & test dump"
    echo "11) Ubah timezone"
    echo "12) Ubah retention days"
    echo "13) Ubah jadwal backup (OnCalendar helper)"
    echo "14) Test backup sekarang"
    echo "15) Restore dari backup"
    echo "16) Rebuild / Repair installer files (service/timer/runner)"
    echo "17) Encrypt latest backup (zip with password)"
    echo "18) Restart service & timer"
    echo "19) Simpan config"
    echo "0) Keluar"
    echo "----------------------------------------------"
    read -p "Pilih menu: " opt
    case "$opt" in
        1) show_status; pause ;;
        2) show_config_file; pause ;;
        3) read -p "Masukkan BOT TOKEN baru: " BOT_TOKEN; echo "[OK] BOT_TOKEN updated."; pause ;;
        4) read -p "Masukkan CHAT ID baru: " CHAT_ID; echo "[OK] CHAT_ID updated."; pause ;;
        5) add_folder; pause ;;
        6) delete_folder; pause ;;
        7) add_mysql; pause ;;
        8) edit_mysql; pause ;;
        9) delete_mysql; pause ;;
        10) edit_pg; pause ;;
        11) read -p "Masukkan timezone (ex: Asia/Jakarta): " NEWTZ; TZ="$NEWTZ"; timedatectl set-timezone "$TZ"; echo "[OK] TZ set to $TZ"; pause ;;
        12) read -p "Masukkan retention days: " RETENTION_DAYS; echo "[OK] Retention set to $RETENTION_DAYS"; pause ;;
        13) build_oncalendar; pause ;;
        14) test_backup; pause ;;
        15) restore_backup; pause ;;
        16) if confirm "Anda yakin ingin (re)build installer files?"; then rebuild_installer_files; fi; pause ;;
        17) encrypt_last_backup; pause ;;
        18) reload_systemd; pause ;;
        19) save_config; pause ;;
        0) echo "Keluar."; break ;;
        *) echo "Pilihan tidak valid."; sleep 1 ;;
    esac
done
EOF

    chmod +x "$INSTALL_DIR/menu.sh"
    echo "[OK] Menu script created: $INSTALL_DIR/menu.sh"

    echo ""
    echo "==========================================="
    echo "INSTALL COMPLETE!"
    echo "Service  : auto-backup.service"
    echo "Timer    : auto-backup.timer"
    echo "Config   : $CONFIG_FILE"
    echo "Backup   : $INSTALL_DIR/backups"
    echo ""
    echo "Untuk membuka menu, jalankan: menu-bot-backup"
    echo "==========================================="

    # run first backup optionally
    if confirm "Jalankan backup pertama sekarang (test)?"; then
        bash "$RUNNER"
        echo "Backup pertama selesai (cek Telegram / $INSTALL_DIR/backups)"
    fi

    echo "Installer selesai."
}

# -------------------------
# Entrypoint
# -------------------------
ensure_root

if [[ "${1:-}" == "--reinstall" ]]; then
    echo "Reinstall mode: existing files may be overwritten."
    if confirm "Lanjutkan reinstall?"; then
        installer
    else
        echo "Batal."
        exit 0
    fi
else
    if [[ -f "$CONFIG_FILE" ]]; then
        echo "Config sudah ada di $CONFIG_FILE."
        if confirm "Ingin menjalankan konfigurasi installer baru (akan menimpa config lama)?"; then
            installer
        else
            echo "Melewati installer. Pastikan file menu sudah ada."
            # ensure menu binary exists
            if [[ ! -x "$MENU_BIN" ]]; then
                echo "Membuat/menimpa menu-bot-backup..."
                mkdir -p "$INSTALL_DIR"
                # create menu wrapper if absent
                cat > "$MENU_BIN" <<'BW'
#!/bin/bash
if [[ -x /opt/auto-backup/menu.sh ]]; then
    exec /opt/auto-backup/menu.sh
else
    echo "Menu belum terpasang. Jalankan installer lagi."
    exit 1
fi
BW
                chmod +x "$MENU_BIN"
                echo "Done."
            fi
            echo "Gunakan: menu-bot-backup"
        fi
    else
        installer
    fi
fi

exit 0
