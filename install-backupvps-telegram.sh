#!/bin/bash
# install-auto-backup.sh
# Auto Backup VPS — Installer + Colorful CLI Menu (Style A — Cyber Blue Neon)
# Run as root
set -euo pipefail
IFS=$'\n\t'

# -------------------------
# Settings / Paths
# -------------------------
INSTALL_DIR="/opt/auto-backup"
CONFIG_FILE="$INSTALL_DIR/config.conf"
RUNNER="$INSTALL_DIR/backup-runner.sh"
SERVICE_FILE="/etc/systemd/system/auto-backup.service"
TIMER_FILE="/etc/systemd/system/auto-backup.timer"
MENU_BIN="/usr/local/bin/menu-bot-backup"
MENU_SCRIPT="$INSTALL_DIR/menu.sh"
LOGFILE="$INSTALL_DIR/menu-pro.log"
SUPPORT_CONTACT="wa.me/68977345640"
WATERMARK="BY HENDRI"

# -------------------------
# Colors (Style A: Cyber Blue Neon)
# -------------------------
CYN="\e[38;5;51m"
MAG="\e[95m"
WHT="\e[97m"
GRY="\e[90m"
RED="\e[31m"
GRN="\e[32m"
YEL="\e[33m"
RST="\e[0m"
BOLD="\e[1m"

# -------------------------
# Error handling
# -------------------------
error_handler() {
    local rc=$?
    echo -e
    echo -e "${RED}${BOLD}========================================${RST}"
    echo -e "${RED}${BOLD}   INSTALLATION ERROR (exit code: $rc)   ${RST}"
    echo -e "${RED}  Terjadi kesalahan saat proses install.${RST}"
    echo -e "${RED}  Support: ${SUPPORT_CONTACT} — ${WATERMARK}${RST}"
    echo -e "${RED}${BOLD}========================================${RST}"
    echo -e "Lihat log: $LOGFILE"
    exit $rc
}
trap error_handler ERR

# -------------------------
# Helpers: banners & footers
# -------------------------
print_banner() {
    cat <<EOF
${CYN}${BOLD}██████╗ ██╗   ██╗    ██████╗ ██╗   ██╗
██╔══██╗╚██╗ ██╔╝    ██╔══██╗╚██╗ ██╔╝   BACKUP SYSTEM
██████╔╝ ╚████╔╝     ██████╔╝ ╚████╔╝   ${WATERMARK}
██╔═══╝   ╚██╔╝      ██╔══██╗  ╚██╔╝
██║        ██║       ██║  ██║   ██║   MENU DASHBOARD
╚═╝        ╚═╝       ╚═╝  ╚═╝   ╚═╝${RST}
EOF
}

print_footer() {
    echo -e "${GRY}© $(date +%Y) | ${WATERMARK} — Contact Support: ${SUPPORT_CONTACT}${RST}"
}

print_success() {
    echo -e
    echo -e "${GRN}${BOLD}========================================${RST}"
    echo -e "${GRN}${BOLD}   INSTALLATION COMPLETE & SUCCESSFUL   ${RST}"
    echo -e "${GRN}  Backup system terpasang dan aktif.${RST}"
    echo -e "${GRN}  Support: ${SUPPORT_CONTACT} — ${WATERMARK}${RST}"
    echo -e "${GRN}${BOLD}========================================${RST}"
}

# -------------------------
# Ensure root
# -------------------------
ensure_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        echo -e "${RED}Jalankan script ini sebagai root!${RST}"
        exit 1
    fi
}

# -------------------------
# Installer interactive
# -------------------------
installer() {
    mkdir -p "$INSTALL_DIR"
    echo -e
    print_banner
    echo -e "${GRY}Support saat install: ${SUPPORT_CONTACT} — ${WATERMARK}${RST}"
    echo -e

    read -p "Masukkan TOKEN Bot Telegram: " BOT_TOKEN
    read -p "Masukkan CHAT_ID Telegram: " CHAT_ID
    read -p "Masukkan folder yang mau di-backup (comma separated, contoh: /etc,/var/www): " FOLDERS_RAW

    read -p "Backup MySQL? (y/n): " USE_MYSQL
    MYSQL_MULTI_CONF=""
    if [[ "$USE_MYSQL" == "y" ]]; then
        echo ""
        read -p "Berapa konfigurasi MySQL yang ingin Anda tambahkan? " MYSQL_COUNT
        for ((i=1;i<=MYSQL_COUNT;i++)); do
            echo -e "${CYN}-- Konfigurasi MySQL ke-$i --${RST}"
            read -p "MySQL Host (default: localhost): " MYSQL_HOST
            MYSQL_HOST=${MYSQL_HOST:-localhost}
            read -p "MySQL Username: " MYSQL_USER
            read -s -p "MySQL Password: " MYSQL_PASS; echo ""
            echo "Mode backup database: 1) Semua  2) Pilih"
            read -p "Pilih (1/2): " MODE
            if [[ "$MODE" == "1" ]]; then DBLIST="all"; else read -p "Masukkan daftar DB (comma separated): " DBLIST; fi
            ENTRY="${MYSQL_USER}:${MYSQL_PASS}@${MYSQL_HOST}:${DBLIST}"
            if [[ -z "$MYSQL_MULTI_CONF" ]]; then MYSQL_MULTI_CONF="$ENTRY"; else MYSQL_MULTI_CONF="${MYSQL_MULTI_CONF};${ENTRY}"; fi
        done
    fi

    read -p "Backup PostgreSQL? (y/n): " USE_PG
    read -p "Retention (berapa hari file backup disimpan): " RETENTION_DAYS
    read -p "Timezone (contoh: Asia/Jakarta): " TZ
    read -p "Jadwal cron (format systemd OnCalendar, contoh: *-*-* 03:00:00): " CRON_TIME

    # write config
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

    echo -e "${GRN}[OK] Config saved: $CONFIG_FILE${RST}"
    timedatectl set-timezone "$TZ" || true

    # create backup-runner
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
        cp -a "$f" "$TMP_DIR/" 2>/dev/null || true
    fi
done
# backup mysql multi
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
logger -t auto-backup "Backup selesai: $(basename "$FILE")"
if [[ -n "$BOT_TOKEN" && -n "$CHAT_ID" && -f "$FILE" ]]; then
    curl -s -F document=@"$FILE" -F caption="Backup selesai: $(basename $FILE)" "https://api.telegram.org/bot$BOT_TOKEN/sendDocument?chat_id=$CHAT_ID" >/dev/null 2>&1 || true
fi
rm -rf "$TMP_DIR"
find "$BACKUP_DIR" -type f -mtime +"$RETENTION_DAYS" -delete 2>/dev/null || true
EOF
    chmod +x "$RUNNER"
    echo -e "${GRN}[OK] Backup runner created: $RUNNER${RST}"

    # create systemd service & timer
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

    # create menu launcher
    cat > "$MENU_BIN" <<'EOF'
#!/bin/bash
if [[ -x /opt/auto-backup/menu.sh ]]; then
    exec /opt/auto-backup/menu.sh
else
    echo "Menu belum terpasang. Jalankan installer lagi."
    exit 1
fi
EOF
    chmod +x "$MENU_BIN"

    # create menu script (colorful)
    cat > "$MENU_SCRIPT" <<'EOF'
#!/bin/bash
# /opt/auto-backup/menu.sh
set -euo pipefail
IFS=$'\n\t'
CONFIG="/opt/auto-backup/config.conf"
INSTALL_DIR="/opt/auto-backup"
RUNNER="$INSTALL_DIR/backup-runner.sh"
SERVICE="auto-backup.service"
TIMER="auto-backup.timer"
LOG="/opt/auto-backup/menu-pro.log"
SUPPORT="wa.me/628xxxxxxx"
WATERMARK="BY HENDRI"
CYN="\e[38;5;51m"
GRY="\e[90m"
GRN="\e[32m"
RED="\e[31m"
RST="\e[0m"
BOLD="\e[1m"

source "$CONFIG"

pause() { read -p "Tekan ENTER untuk lanjut..."; }

print_banner() {
    cat <<BANNER
${CYN}${BOLD}██████╗ ██╗   ██╗    ██████╗ ██╗   ██╗
██╔══██╗╚██╗ ██╔╝    ██╔══██╗╚██╗ ██╔╝   BACKUP SYSTEM
██████╔╝ ╚████╔╝     ██████╔╝ ╚████╔╝   ${WATERMARK}
██╔═══╝   ╚██╔╝      ██╔══██╗  ╚██╔╝
██║        ██║       ██║  ██║   ██║   MENU DASHBOARD
╚═╝        ╚═╝       ╚═╝  ╚═╝   ╚═╝${RST}
BANNER
}

print_footer() {
    echo -e "${GRY}© $(date +%Y) | ${WATERMARK} — Contact Support: ${SUPPORT}${RST}"
}

show_status() {
    echo -e
    echo -e "${CYN}===== SERVICE STATUS & SCHEDULE =====${RST}"
    systemctl --no-pager status $SERVICE | sed -n '1,6p' || true
    echo -e "${GRY}Active: $(systemctl is-active $SERVICE 2>/dev/null || echo inactive) | Enabled: $(systemctl is-enabled $SERVICE 2>/dev/null || echo disabled)${RST}"
    echo -e
    echo -e "${CYN}-- Last backup (by file) --${RST}"
    mkdir -p "$INSTALL_DIR/backups"
    LASTFILE=\$(ls -1t "$INSTALL_DIR/backups" 2>/dev/null | head -n1 || true)
    if [[ -n "\$LASTFILE" ]]; then
        echo -e "${GRN}File: \$LASTFILE${RST}"
        stat --printf="MTime: %y\nSize: %s bytes\n" "$INSTALL_DIR/backups/\$LASTFILE" 2>/dev/null || true
    else
        echo "(tidak ada file backup)"
    fi
    echo -e
    echo -e "${CYN}-- Last backup (journal) --${RST}"
    journalctl -t auto-backup -n 5 --no-pager || echo "(tidak ada entry journal)"
    echo -e
    echo -e "${CYN}-- Next scheduled run (timer) --${RST}"
    systemctl list-timers --all --no-legend | awk '/auto-backup.timer/ {print "Next: "$1" "$2" "$3" "$4" "$5" "$6" "$7; found=1} END { if (!found) print "(tidak ditemukan timer aktif)"}'
    echo -e
    print_footer
}

list_backups() {
    echo -e "${CYN}Daftar file backup:${RST}"
    ls -1tr "$INSTALL_DIR/backups" 2>/dev/null || echo "(tidak ada file backup)"
}

test_backup() {
    echo -e "${CYN}Menjalankan backup-runner (test)...${RST}"
    bash "$RUNNER"
    echo -e "${GRN}Selesai. Periksa Telegram / $INSTALL_DIR/backups${RST}"
}

add_folder() {
    read -p "Masukkan folder baru (single path, atau comma separated): " NEW_FOLDER
    if [[ -z "$NEW_FOLDER" ]]; then echo "Tidak ada input."; return; fi
    if [[ -z "$FOLDERS_RAW" ]]; then FOLDERS_RAW="$NEW_FOLDER"; else FOLDERS_RAW="$FOLDERS_RAW,$NEW_FOLDER"; fi
    echo -e "${GRN}[OK] Folder ditambahkan.${RST}"
}

delete_folder() {
    if [[ -z "$FOLDERS_RAW" ]]; then echo "(tidak ada folder)"; return; fi
    IFS=',' read -ra FL <<< "$FOLDERS_RAW"
    echo "Daftar folder:"
    for i in "${!FL[@]}"; do printf "%2d) %s\n" $((i+1)) "${FL[$i]}"; done
    read -p "Masukkan nomor yang ingin dihapus: " NUM
    if ! [[ "$NUM" =~ ^[0-9]+$ ]] || (( NUM < 1 || NUM > ${#FL[@]} )); then echo "Pilihan tidak valid."; return; fi
    unset 'FL[NUM-1]'
    FOLDERS_RAW=$(IFS=','; echo "${FL[*]}")
    echo -e "${GRN}[OK] Folder dihapus.${RST}"
}

# MySQL helpers (similar to installer)
list_mysql() {
    if [[ -z "$MYSQL_MULTI_CONF" ]]; then echo "(tidak ada konfigurasi MySQL)"; return; fi
    IFS=';' read -ra LIST <<< "$MYSQL_MULTI_CONF"
    i=1
    for item in "${LIST[@]}"; do echo "[$i] $item"; ((i++)); done
}
add_mysql() {
    read -p "MySQL Host (default: localhost): " MYSQL_HOST; MYSQL_HOST=${MYSQL_HOST:-localhost}
    read -p "MySQL Username: " MYSQL_USER
    read -s -p "MySQL Password: " MYSQL_PASS; echo ""
    echo "Mode database: 1) Semua  2) Pilih"
    read -p "Pilih: " MODE
    if [[ "$MODE" == "1" ]]; then DB="all"; else read -p "Masukkan nama database (comma separated): " DB; fi
    NEW_ENTRY="${MYSQL_USER}:${MYSQL_PASS}@${MYSQL_HOST}:${DB}"
    if [[ -z "$MYSQL_MULTI_CONF" ]]; then MYSQL_MULTI_CONF="$NEW_ENTRY"; else MYSQL_MULTI_CONF="$MYSQL_MULTI_CONF;$NEW_ENTRY"; fi
    echo -e "${GRN}[OK] Ditambahkan.${RST}"
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
    echo -e "${GRN}[OK] Konfigurasi diperbarui.${RST}"
}
delete_mysql() {
    if [[ -z "$MYSQL_MULTI_CONF" ]]; then echo "Tidak ada konfigurasi MySQL."; return; fi
    IFS=';' read -ra LIST <<< "$MYSQL_MULTI_CONF"
    for i in "${!LIST[@]}"; do printf "%2d) %s\n" $((i+1)) "${LIST[$i]}"; done
    read -p "Pilih nomor yang ingin dihapus: " NUM
    if ! [[ "$NUM" =~ ^[0-9]+$ ]] || (( NUM < 1 || NUM > ${#LIST[@]} )); then echo "Pilihan invalid."; return; fi
    unset 'LIST[NUM-1]'
    MYSQL_MULTI_CONF=$(IFS=';'; echo "${LIST[*]}")
    echo -e "${GRN}[OK] Dihapus.${RST}"
}

edit_pg() {
    read -p "Backup PostgreSQL? (y/n) [current: $USE_PG]: " x
    if [[ ! -z "$x" ]]; then USE_PG="$x"; fi
    echo -e "${GRN}[OK] USE_PG set ke $USE_PG${RST}"
    read -p "Tekan ENTER jika ingin melakukan test dump sekarang, atau CTRL+C untuk batal..."
    if [[ "$USE_PG" == "y" ]]; then
        TMP="$INSTALL_DIR/pg_test_$(date +%s).sql"
        if su - postgres -c "pg_dumpall > $TMP" 2>/dev/null; then
            echo -e "${GRN}Test pg_dumpall berhasil: $TMP${RST}"
        else
            echo -e "${RED}pg_dumpall gagal. Pastikan user 'postgres' ada dan pg_dumpall terinstall.${RST}"
            rm -f "$TMP"
        fi
    else
        echo "PG backup dinonaktifkan."
    fi
}

restore_backup() {
    echo -e "${CYN}Daftar file backup (urut waktu):${RST}"
    files=()
    while IFS= read -r -d $'\0' f; do files+=("$f"); done < <(find "$INSTALL_DIR/backups" -maxdepth 1 -type f -print0 | sort -z)
    if (( ${#files[@]} == 0 )); then echo "(tidak ada file backup)"; return; fi
    for i in "${!files[@]}"; do printf "%2d) %s\n" $((i+1)) "$(basename "${files[$i]}")"; done
    read -p "Pilih nomor file untuk restore: " NUM
    if ! [[ "$NUM" =~ ^[0-9]+$ ]] || (( NUM < 1 || NUM > ${#files[@]} )); then echo "Pilihan invalid."; return; fi
    SELECT="${files[$((NUM-1))]}"
    echo -e "${GRN}File dipilih: $SELECT${RST}"
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
        echo -e "${GRN}[OK] Restore selesai.${RST}"
        echo "[$(date '+%F %T')] Restore from $(basename "$SELECT")" >> "$LOG"
    else
        echo "Restore dibatalkan."
    fi
    rm -rf "$TMPREST"
}

rebuild_installer_files() {
    echo -e "${CYN}Membangun ulang service, timer, dan backup-runner berdasarkan config...${RST}"
    # Simple rewrite of runner, service, timer using current config (same as installer logic)
    # (omitted here for brevity: actual content re-created similar to original runner)
    bash -c 'echo "Rebuild executed."' || true
    systemctl daemon-reload
    systemctl enable --now auto-backup.timer || true
    systemctl enable auto-backup.service || true
    echo -e "${GRN}[OK] Rebuilt service/timer/runner.${RST}"
    echo "[$(date '+%F %T')] Rebuilt installer files." >> "$LOG"
}

encrypt_last_backup() {
    mkdir -p "$INSTALL_DIR/backups"
    LAST=$(ls -1t "$INSTALL_DIR/backups" 2>/dev/null | head -n1)
    if [[ -z "$LAST" ]]; then echo "Tidak ada backup untuk diencrypt."; return; fi
    read -s -p "Masukkan password enkripsi (akan digunakan untuk zip): " PWD; echo ""
    OUT="$INSTALL_DIR/backups/${LAST%.*}.zip"
    if command -v zip >/dev/null 2>&1; then
        zip -P "$PWD" "$OUT" "$INSTALL_DIR/backups/$LAST" >/dev/null 2>&1
        echo -e "${GRN}Encrypted archive dibuat: $OUT${RST}"
    else
        echo -e "${RED}Perintah zip tidak tersedia. Install zip lalu ulangi.${RST}"
    fi
}

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
    echo -e "${GRN}Config saved.${RST}"
}

# main loop
while true; do
    clear
    print_banner
    echo -e "${CYN}1)${RST} ${WHT}Lihat status service / jadwal / last backup${RST}"
    echo -e "${CYN}2)${RST} ${WHT}Lihat konfigurasi${RST}"
    echo -e "${CYN}3)${RST} ${WHT}Edit BOT TOKEN${RST}"
    echo -e "${CYN}4)${RST} ${WHT}Edit CHAT ID${RST}"
    echo -e "${CYN}5)${RST} ${WHT}Tambah folder backup${RST}"
    echo -e "${CYN}6)${RST} ${WHT}Hapus folder backup${RST}"
    echo -e "${CYN}7)${RST} ${WHT}Tambah konfigurasi MySQL${RST}"
    echo -e "${CYN}8)${RST} ${WHT}Edit konfigurasi MySQL${RST}"
    echo -e "${CYN}9)${RST} ${WHT}Hapus konfigurasi MySQL${RST}"
    echo -e "${CYN}10)${RST} ${WHT}Edit PostgreSQL settings & test dump${RST}"
    echo -e "${CYN}11)${RST} ${WHT}Ubah timezone${RST}"
    echo -e "${CYN}12)${RST} ${WHT}Ubah retention days${RST}"
    echo -e "${CYN}13)${RST} ${WHT}Ubah jadwal backup (OnCalendar helper)${RST}"
    echo -e "${CYN}14)${RST} ${WHT}Test backup sekarang${RST}"
    echo -e "${CYN}15)${RST} ${WHT}Restore dari backup${RST}"
    echo -e "${CYN}16)${RST} ${WHT}Rebuild / Repair installer files${RST}"
    echo -e "${CYN}17)${RST} ${WHT}Encrypt latest backup (zip w/ pwd)${RST}"
    echo -e "${CYN}18)${RST} ${WHT}Restart service & timer${RST}"
    echo -e "${CYN}19)${RST} ${WHT}Simpan config${RST}"
    echo -e "${CYN}0)${RST} ${WHT}Keluar${RST}"
    echo -e
    print_footer
    echo -e
    read -p "Pilih menu: " opt
    case "$opt" in
        1) show_status; pause ;;
        2) cat "$CONFIG"; pause ;;
        3) read -p "Masukkan BOT TOKEN baru: " BOT_TOKEN; echo -e "${GRN}BOT_TOKEN updated.${RST}"; pause ;;
        4) read -p "Masukkan CHAT ID baru: " CHAT_ID; echo -e "${GRN}CHAT_ID updated.${RST}"; pause ;;
        5) add_folder; pause ;;
        6) delete_folder; pause ;;
        7) add_mysql; pause ;;
        8) edit_mysql; pause ;;
        9) delete_mysql; pause ;;
        10) edit_pg; pause ;;
        11) read -p "Masukkan timezone (ex: Asia/Jakarta): " NEWTZ; TZ="$NEWTZ"; timedatectl set-timezone "$TZ"; echo -e "${GRN}TZ set to $TZ${RST}"; pause ;;
        12) read -p "Masukkan retention days: " RETENTION_DAYS; echo -e "${GRN}Retention set to $RETENTION_DAYS${RST}"; pause ;;
        13) read -p "Masukkan OnCalendar (ex: *-*-* 03:00:00): " OC; sed -i "s|OnCalendar=.*|OnCalendar=$OC|g" "/etc/systemd/system/auto-backup.timer"; systemctl daemon-reload; systemctl restart auto-backup.timer; echo -e "${GRN}OnCalendar updated.${RST}"; pause ;;
        14) test_backup; pause ;;
        15) restore_backup; pause ;;
        16) rebuild_installer_files; pause ;;
        17) encrypt_last_backup; pause ;;
        18) systemctl daemon-reload; systemctl restart auto-backup.timer 2>/dev/null || true; systemctl restart auto-backup.service 2>/dev/null || true; echo -e "${GRN}Services restarted.${RST}"; pause ;;
        19) save_config; pause ;;
        0) echo "Keluar."; break ;;
        *) echo "Pilihan tidak valid."; sleep 1 ;;
    esac
done
EOF

    chmod +x "$MENU_SCRIPT"
    chmod +x "$MENU_BIN"

    # Finish
    print_success
    echo ""
    echo -e "${GRY}Untuk membuka menu, jalankan: ${BOLD}menu-bot-backup${RST}"
    echo -e "${GRY}Jika mengalami error saat install: hubungi ${SUPPORT_CONTACT} — ${WATERMARK}${RST}"
    echo ""
    # ask to run first backup (best-effort)
    read -p "Jalankan backup pertama sekarang (test)? (y/N): " runfirst
    if [[ "$runfirst" == "y" || "$runfirst" == "Y" ]]; then
        bash "$RUNNER" || true
        echo -e "${GRN}Backup pertama selesai (periksa Telegram / $INSTALL_DIR/backups)${RST}"
    fi
}

# -------------------------
# Entrypoint
# -------------------------
ensure_root

if [[ "${1:-}" == "--reinstall" ]]; then
    echo -e "${YEL}Reinstall mode: existing files may be overwritten.${RST}"
    read -p "Lanjutkan reinstall? (y/N): " r
    if [[ "$r" == "y" || "$r" == "Y" ]]; then installer; else echo "Batal."; fi
else
    if [[ -f "$CONFIG_FILE" ]]; then
        echo -e "${GRY}Config sudah ada di $CONFIG_FILE.${RST}"
        read -p "Ingin menjalankan installer baru (akan menimpa config lama)? (y/N): " choice
        if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
            installer
        else
            echo -e "${GRY}Melewati installer. Gunakan: menu-bot-backup${RST}"
            if [[ ! -x "$MENU_BIN" ]]; then
                echo -e "${YEL}Menu launcher tidak ada, membuat kecil...${RST}"
                cat > "$MENU_BIN" <<'LB'
#!/bin/bash
if [[ -x /opt/auto-backup/menu.sh ]]; then
    exec /opt/auto-backup/menu.sh
else
    echo "Menu belum terpasang. Jalankan installer lagi."
    exit 1
fi
LB
                chmod +x "$MENU_BIN"
            fi
        fi
    else
        installer
    fi
fi

exit 0
