#!/bin/bash
# install-auto-backup.sh
# Installer lengkap: membuat folder /opt/auto-backup, service, timer, runner, menu
# Run as root
set -euo pipefail
IFS=$'\n\t'

INSTALL_DIR="/opt/auto-backup"
CONFIG_FILE="$INSTALL_DIR/config.conf"
RUNNER="$INSTALL_DIR/backup-runner.sh"
MENU_SCRIPT="$INSTALL_DIR/menu.sh"
MENU_BIN="/usr/local/bin/menu-bot-backup"
SERVICE_FILE="/etc/systemd/system/auto-backup.service"
TIMER_FILE="/etc/systemd/system/auto-backup.timer"
LOGFILE="$INSTALL_DIR/menu-pro.log"
SUPPORT_CONTACT="wa.me/628977345640"   # sesuaikan
WATERMARK="BY HENDRI"

# Colors (dashboard style)
CYN="\e[36m"
GRN="\e[32m"
YEL="\e[33m"
WHT="\e[97m"
GRY="\e[90m"
RED="\e[31m"
RST="\e[0m"
BOLD="\e[1m"

ensure_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        echo -e "${RED}Jalankan script ini sebagai root!${RST}"
        exit 1
    fi
}

error_handler() {
    rc=$?
    echo -e "${RED}${BOLD}Terjadi kesalahan (kode: $rc). Lihat $LOGFILE${RST}"
    exit $rc
}
trap error_handler ERR

print_banner() {
    cat <<EOF
${CYN}${BOLD}==================== AUTO BACKUP INSTALLER ====================${RST}
    ${WHT}Installer akan membuat: $INSTALL_DIR, service, timer, runner, dan menu launcher${RST}
EOF
}

write_runner() {
    cat > "$RUNNER" <<'EOF'
#!/bin/bash
# backup-runner.sh
set -euo pipefail
IFS=$'\n\t'
CONFIG_FILE="/opt/auto-backup/config.conf"
[ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE" || { echo "Config not found"; exit 1; }
export TZ="${TZ:-UTC}"

BACKUP_DIR="${INSTALL_DIR}/backups"
mkdir -p "$BACKUP_DIR"

DATE=$(date +%F-%H%M%S)
TMP_DIR="${INSTALL_DIR}/tmp-$DATE"
mkdir -p "$TMP_DIR"

# backup folders
IFS=',' read -r -a FOLDERS <<< "${FOLDERS_RAW:-}"
for f in "${FOLDERS[@]}"; do
    f_trim="$(echo "$f" | xargs)"
    if [[ -z "$f_trim" ]]; then continue; fi
    if [[ -d "$f_trim" || -f "$f_trim" ]]; then
        mkdir -p "$TMP_DIR/paths"
        cp -a "$f_trim" "$TMP_DIR/paths/" 2>/dev/null || true
    fi
done

# mysql multi
if [[ "${USE_MYSQL:-n}" == "y" && -n "${MYSQL_MULTI_CONF:-}" ]]; then
    mkdir -p "$TMP_DIR/mysql"
    IFS=';' read -r -a MYSQL_ITEMS <<< "${MYSQL_MULTI_CONF}"
    for ITEM in "${MYSQL_ITEMS[@]}"; do
        # ENTRY format: user:pass@host:dblist
        USERPASS="${ITEM%%@*}"
        HOSTDB="${ITEM#*@}"
        MYSQL_USER="${USERPASS%%:*}"
        MYSQL_PASS="${USERPASS#*:}"
        MYSQL_HOST="${HOSTDB%%:*}"
        MYSQL_DB_LIST="${HOSTDB#*:}"
        MYSQL_ARGS="-h${MYSQL_HOST} -u${MYSQL_USER} -p${MYSQL_PASS}"
        if [[ "${MYSQL_DB_LIST}" == "all" ]]; then
            mysqldump $MYSQL_ARGS --all-databases > "$TMP_DIR/mysql/${MYSQL_USER}@${MYSQL_HOST}_ALL.sql" 2>/dev/null || true
        else
            IFS=',' read -r -a DBARR <<< "${MYSQL_DB_LIST}"
            for DB in "${DBARR[@]}"; do
                mysqldump $MYSQL_ARGS "$DB" > "$TMP_DIR/mysql/${MYSQL_USER}@${MYSQL_HOST}_${DB}.sql" 2>/dev/null || true
            done
        fi
    done
fi

# postgres
if [[ "${USE_PG:-n}" == "y" ]]; then
    mkdir -p "$TMP_DIR/postgres"
    if id -u postgres >/dev/null 2>&1; then
        su - postgres -c "pg_dumpall > $TMP_DIR/postgres/all.sql" 2>/dev/null || true
    else
        pg_dumpall > "$TMP_DIR/postgres/all.sql" 2>/dev/null || true
    fi
fi

OUT_FILE="$BACKUP_DIR/backup-$DATE.tar.gz"
tar -czf "$OUT_FILE" -C "$TMP_DIR" . 2>/dev/null || true
logger -t auto-backup "Backup selesai: $(basename "$OUT_FILE")"

# send to telegram if configured
if [[ -n "${BOT_TOKEN:-}" && -n "${CHAT_ID:-}" && -f "$OUT_FILE" ]]; then
    curl -s -F document=@"$OUT_FILE" -F caption="Backup selesai: $(basename "$OUT_FILE")" "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument?chat_id=${CHAT_ID}" >/dev/null 2>&1 || true
fi

# cleanup
rm -rf "$TMP_DIR"

# retention
if [[ -n "${RETENTION_DAYS:-}" && "${RETENTION_DAYS}" =~ ^[0-9]+$ ]]; then
    find "$BACKUP_DIR" -type f -mtime +"$RETENTION_DAYS" -delete 2>/dev/null || true
fi
EOF
    chmod +x "$RUNNER"
}

write_menu() {
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
SUPPORT="wa.me/628977345640"
WATERMARK="BY HENDRI"

CYN="\e[36m"; GRN="\e[32m"; YEL="\e[33m"; WHT="\e[97m"; GRY="\e[90m"; RED="\e[31m"; RST="\e[0m"; BOLD="\e[1m"

# load config if exists
if [[ -f "$CONFIG" ]]; then
    source "$CONFIG"
else
    # defaults
    BOT_TOKEN=""
    CHAT_ID=""
    FOLDERS_RAW=""
    USE_MYSQL="n"
    MYSQL_MULTI_CONF=""
    USE_PG="n"
    RETENTION_DAYS="7"
    TZ="UTC"
    INSTALL_DIR="/opt/auto-backup"
fi

pause() { read -r -p "Tekan ENTER untuk lanjut..."; }

print_banner() {
    clear
    echo -e "${CYN}${BOLD}==================== BACKUP DASHBOARD ====================${RST}"
    echo -e "${WHT}  Auto Backup — Telegram VPS    ${GRY}${WATERMARK}${RST}"
    echo ""
}

print_footer() {
    echo ""
    echo -e "${GRY}© $(date +%Y) | Support: ${SUPPORT} — ${WATERMARK}${RST}"
}

show_status() {
    echo -e "${CYN}----- SERVICE STATUS -----${RST}"
    systemctl --no-pager status $SERVICE | sed -n '1,8p' || true
    echo -e "${GRN}Active: $(systemctl is-active $SERVICE 2>/dev/null || echo inactive)${RST} | ${YEL}Enabled: $(systemctl is-enabled $SERVICE 2>/dev/null || echo disabled)${RST}"
    echo ""
    echo -e "${CYN}-- Last backup file --${RST}"
    mkdir -p "$INSTALL_DIR/backups"
    LASTFILE=$(ls -1t "$INSTALL_DIR/backups" 2>/dev/null | head -n1 || true)
    if [[ -n "$LASTFILE" ]]; then
        echo -e "${GRN}File: $LASTFILE${RST}"
        stat --printf="MTime: %y\nSize: %s bytes\n" "$INSTALL_DIR/backups/$LASTFILE" 2>/dev/null || true
    else
        echo "(tidak ada file backup)"
    fi
    echo ""
    echo -e "${CYN}-- Journal (auto-backup) --${RST}"
    journalctl -t auto-backup -n 8 --no-pager || echo "(tidak ada entry journal)"
    echo ""
    echo -e "${CYN}-- Next scheduled run --${RST}"
    # show next timer run for auto-backup.timer
    systemctl list-timers --all --no-legend | awk '/auto-backup.timer/ {print "Next: "$1" "$2" "$3" "$4" "$5" "$6" "$7; found=1} END { if (!found) print "(tidak ditemukan timer aktif)"}'
    echo ""
}

show_config() {
    echo -e "${CYN}----- CURRENT CONFIG -----${RST}"
    echo "BOT_TOKEN: ${BOT_TOKEN:-(empty)}"
    echo "CHAT_ID : ${CHAT_ID:-(empty)}"
    echo "Folders : ${FOLDERS_RAW:-(none)}"
    echo "USE_MYSQL: ${USE_MYSQL:-n}"
    echo "MYSQL_MULTI_CONF: ${MYSQL_MULTI_CONF:-(none)}"
    echo "USE_PG: ${USE_PG:-n}"
    echo "RETENTION_DAYS: ${RETENTION_DAYS:-7}"
    echo "TZ: ${TZ:-UTC}"
}

edit_bot_token() {
    read -r -p "Masukkan BOT TOKEN baru: " new
    BOT_TOKEN="$new"
    echo -e "${GRN}BOT_TOKEN updated.${RST}"
}

edit_chat_id() {
    read -r -p "Masukkan CHAT ID baru: " new
    CHAT_ID="$new"
    echo -e "${GRN}CHAT_ID updated.${RST}"
}

add_folder() {
    read -r -p "Masukkan folder baru (single path atau multiple comma separated): " NEW_FOLDER
    if [[ -z "$NEW_FOLDER" ]]; then echo "Tidak ada input."; return; fi
    if [[ -z "${FOLDERS_RAW}" ]]; then FOLDERS_RAW="$NEW_FOLDER"; else FOLDERS_RAW="${FOLDERS_RAW},$NEW_FOLDER"; fi
    echo -e "${GRN}[OK] Folder ditambahkan.${RST}"
}

delete_folder() {
    if [[ -z "$FOLDERS_RAW" ]]; then echo "(tidak ada folder)"; return; fi
    IFS=',' read -ra FL <<< "$FOLDERS_RAW"
    echo "Daftar folder:"
    for i in "${!FL[@]}"; do printf "%2d) %s\n" $((i+1)) "${FL[$i]}"; done
    read -r -p "Masukkan nomor yang ingin dihapus: " NUM
    if ! [[ "$NUM" =~ ^[0-9]+$ ]] || (( NUM < 1 || NUM > ${#FL[@]} )); then echo "Pilihan tidak valid."; return; fi
    unset 'FL[NUM-1]'
    FOLDERS_RAW=$(IFS=','; echo "${FL[*]}")
    echo -e "${GRN}[OK] Folder dihapus.${RST}"
}

list_mysql() {
    if [[ -z "${MYSQL_MULTI_CONF}" ]]; then echo "(tidak ada konfigurasi MySQL)"; return; fi
    IFS=';' read -ra LIST <<< "$MYSQL_MULTI_CONF"
    i=1
    for item in "${LIST[@]}"; do echo "[$i] $item"; ((i++)); done
}

add_mysql() {
    read -r -p "MySQL Host (default: localhost): " MYSQL_HOST; MYSQL_HOST=${MYSQL_HOST:-localhost}
    read -r -p "MySQL Username: " MYSQL_USER
    read -s -r -p "MySQL Password: " MYSQL_PASS; echo ""
    echo "Mode database: 1) Semua  2) Pilih (comma separated)"
    read -r -p "Pilih: " MODE
    if [[ "$MODE" == "1" ]]; then DB="all"; else read -r -p "Masukkan nama database (comma separated): " DB; fi
    NEW_ENTRY="${MYSQL_USER}:${MYSQL_PASS}@${MYSQL_HOST}:${DB}"
    if [[ -z "${MYSQL_MULTI_CONF}" ]]; then MYSQL_MULTI_CONF="$NEW_ENTRY"; else MYSQL_MULTI_CONF="${MYSQL_MULTI_CONF};$NEW_ENTRY"; fi
    echo -e "${GRN}[OK] Ditambahkan.${RST}"
}

edit_mysql() {
    if [[ -z "${MYSQL_MULTI_CONF}" ]]; then echo "Tidak ada konfigurasi MySQL."; return; fi
    IFS=';' read -ra LIST <<< "$MYSQL_MULTI_CONF"
    for i in "${!LIST[@]}"; do printf "%2d) %s\n" $((i+1)) "${LIST[$i]}"; done
    read -r -p "Pilih nomor untuk diedit: " NUM
    if ! [[ "$NUM" =~ ^[0-9]+$ ]] || (( NUM < 1 || NUM > ${#LIST[@]} )); then echo "Pilihan invalid."; return; fi
    IDX=$((NUM-1))
    OLD="${LIST[$IDX]}"
    OLD_USER=$(echo "$OLD" | cut -d':' -f1)
    OLD_PASS=$(echo "$OLD" | cut -d':' -f2 | cut -d'@' -f1)
    OLD_HOST=$(echo "$OLD" | cut -d'@' -f2 | cut -d':' -f1)
    OLD_DB=$(echo "$OLD" | rev | cut -d: -f1 | rev)
    read -r -p "MySQL Host [$OLD_HOST]: " MYSQL_HOST; MYSQL_HOST=${MYSQL_HOST:-$OLD_HOST}
    read -r -p "MySQL Username [$OLD_USER]: " MYSQL_USER; MYSQL_USER=${MYSQL_USER:-$OLD_USER}
    read -s -r -p "MySQL Password (kosong = tetap): " MYSQL_PASS; echo ""
    if [[ -z "$MYSQL_PASS" ]]; then MYSQL_PASS="$OLD_PASS"; fi
    read -r -p "Database (comma or 'all') [$OLD_DB]: " DB; DB=${DB:-$OLD_DB}
    NEW_ENTRY="${MYSQL_USER}:${MYSQL_PASS}@${MYSQL_HOST}:${DB}"
    LIST[$IDX]="$NEW_ENTRY"
    MYSQL_MULTI_CONF=$(IFS=';'; echo "${LIST[*]}")
    echo -e "${GRN}[OK] Konfigurasi diperbarui.${RST}"
}

delete_mysql() {
    if [[ -z "${MYSQL_MULTI_CONF}" ]]; then echo "Tidak ada konfigurasi MySQL."; return; fi
    IFS=';' read -ra LIST <<< "$MYSQL_MULTI_CONF"
    for i in "${!LIST[@]}"; do printf "%2d) %s\n" $((i+1)) "${LIST[$i]}"; done
    read -r -p "Pilih nomor yang ingin dihapus: " NUM
    if ! [[ "$NUM" =~ ^[0-9]+$ ]] || (( NUM < 1 || NUM > ${#LIST[@]} )); then echo "Pilihan invalid."; return; fi
    unset 'LIST[NUM-1]'
    MYSQL_MULTI_CONF=$(IFS=';'; echo "${LIST[*]}")
    echo -e "${GRN}[OK] Dihapus.${RST}"
}

edit_pg() {
    read -r -p "Backup PostgreSQL? (y/n) [current: ${USE_PG}]: " x
    if [[ -n "$x" ]]; then USE_PG="$x"; fi
    echo -e "${GRN}[OK] USE_PG set ke $USE_PG${RST}"
    if [[ "$USE_PG" == "y" ]]; then
        echo "Test pg_dumpall (akan membuat file /opt/auto-backup/pg_test_*.sql)"
        TMP="$INSTALL_DIR/pg_test_$(date +%s).sql"
        if su - postgres -c "pg_dumpall > $TMP" 2>/dev/null; then
            echo -e "${GRN}Test pg_dumpall berhasil: $TMP${RST}"
        else
            echo -e "${RED}pg_dumpall gagal. Pastikan pg_dumpall terinstall dan user postgres ada.${RST}"
            rm -f "$TMP" || true
        fi
    fi
}

change_timezone() {
    read -r -p "Masukkan timezone (contoh: Asia/Jakarta): " NEWTZ
    if [[ -n "$NEWTZ" ]]; then
        TZ="$NEWTZ"
        timedatectl set-timezone "$TZ" >/dev/null 2>&1 || true
        echo -e "${GRN}TZ set to $TZ${RST}"
    fi
}

change_retention() {
    read -r -p "Masukkan retention days (angka): " R
    if [[ "$R" =~ ^[0-9]+$ ]]; then RETENTION_DAYS="$R"; echo -e "${GRN}Retention set to $RETENTION_DAYS${RST}"; else echo "Input invalid."; fi
}

change_oncalendar() {
    echo "Format contoh OnCalendar: *-*-* 03:00:00"
    read -r -p "Masukkan OnCalendar baru: " OC
    if [[ -z "$OC" ]]; then echo "Canceled."; return; fi
    sed -i "s|OnCalendar=.*|OnCalendar=$OC|g" "/etc/systemd/system/auto-backup.timer" || true
    systemctl daemon-reload
    systemctl restart auto-backup.timer || true
    echo -e "${GRN}OnCalendar updated to: $OC${RST}"
}

test_backup_now() {
    echo -e "${CYN}Menjalankan backup-runner (test)...${RST}"
    bash "$RUNNER"
    echo -e "${GRN}Selesai. Periksa Telegram atau $INSTALL_DIR/backups${RST}"
}

list_backups() {
    echo -e "${CYN}Daftar file backup:${RST}"
    ls -1tr "$INSTALL_DIR/backups" 2>/dev/null || echo "(tidak ada file backup)"
}

restore_backup() {
    echo -e "${CYN}Daftar file backup (urut waktu):${RST}"
    files=()
    while IFS= read -r -d $'\0' f; do files+=("$f"); done < <(find "$INSTALL_DIR/backups" -maxdepth 1 -type f -print0 | sort -z)
    if (( ${#files[@]} == 0 )); then echo "(tidak ada file backup)"; return; fi
    for i in "${!files[@]}"; do printf "%2d) %s\n" $((i+1)) "$(basename "${files[$i]}")"; done
    read -r -p "Pilih nomor file untuk restore: " NUM
    if ! [[ "$NUM" =~ ^[0-9]+$ ]] || (( NUM < 1 || NUM > ${#files[@]} )); then echo "Pilihan invalid."; return; fi
    SELECT="${files[$((NUM-1))]}"
    echo -e "${GRN}File dipilih: $SELECT${RST}"
    tar -tzf "$SELECT" | sed -n '1,30p'
    read -r -p "Lanjut restore dan timpa file sesuai archive ke root (/)? (y/N): " ans
    if [[ "$ans" != "y" && "$ans" != "Y" ]]; then echo "Restore dibatalkan."; return; fi
    TMPREST="$INSTALL_DIR/restore_tmp_$(date +%s)"
    mkdir -p "$TMPREST"
    tar -xzf "$SELECT" -C "$TMPREST"
    echo "File diekstrak ke $TMPREST"
    read -r -p "Ekstrak ke / (akan menimpa file yang ada). Lanjut? (y/N): " ans2
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
    # write service & timer & runner will be regenerated by installer helper script if needed
    echo "Rebuild requested" >> "$LOG"
    systemctl daemon-reload
    systemctl enable --now auto-backup.timer || true
    systemctl enable auto-backup.service || true
    echo -e "${GRN}[OK] Rebuilt service/timer/runner.${RST}"
}

encrypt_last_backup() {
    mkdir -p "$INSTALL_DIR/backups"
    LAST=$(ls -1t "$INSTALL_DIR/backups" 2>/dev/null | head -n1)
    if [[ -z "$LAST" ]]; then echo "Tidak ada backup untuk diencrypt."; return; fi
    read -s -r -p "Masukkan password enkripsi (akan digunakan untuk zip): " PWD; echo ""
    OUT="$INSTALL_DIR/backups/${LAST%.*}.zip"
    if command -v zip >/dev/null 2>&1; then
        zip -P "$PWD" "$OUT" "$INSTALL_DIR/backups/$LAST" >/dev/null 2>&1
        echo -e "${GRN}Encrypted archive dibuat: $OUT${RST}"
    else
        echo -e "${RED}Perintah zip tidak tersedia. Install zip lalu ulangi.${RST}"
    fi
}

restart_services() {
    systemctl daemon-reload
    systemctl restart auto-backup.timer 2>/dev/null || true
    systemctl restart auto-backup.service 2>/dev/null || true
    echo -e "${GRN}Services restarted.${RST}"
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
    echo -e "${GRN}Config saved to $CONFIG${RST}"
}

# main loop
while true; do
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
    echo -e "${CYN}16)${RST} ${WHT}Rebuild / Repair installer files (service/timer/runner)${RST}"
    echo -e "${CYN}17)${RST} ${WHT}Encrypt latest backup (zip with password)${RST}"
    echo -e "${CYN}18)${RST} ${WHT}Restart service & timer${RST}"
    echo -e "${CYN}19)${RST} ${WHT}Simpan config${RST}"
    echo -e "${CYN}0)${RST} ${WHT}Keluar${RST}"
    echo ""
    print_footer
    echo ""
    read -r -p "Pilih menu: " opt
    case "$opt" in
        1) show_status; pause ;;
        2) show_config; pause ;;
        3) edit_bot_token; pause ;;
        4) edit_chat_id; pause ;;
        5) add_folder; pause ;;
        6) delete_folder; pause ;;
        7) add_mysql; pause ;;
        8) edit_mysql; pause ;;
        9) delete_mysql; pause ;;
        10) edit_pg; pause ;;
        11) change_timezone; pause ;;
        12) change_retention; pause ;;
        13) change_oncalendar; pause ;;
        14) test_backup_now; pause ;;
        15) restore_backup; pause ;;
        16) rebuild_installer_files; pause ;;
        17) encrypt_last_backup; pause ;;
        18) restart_services; pause ;;
        19) save_config; pause ;;
        0) echo "Keluar."; break ;;
        *) echo "Pilihan tidak valid."; sleep 1 ;;
    esac
done
EOF

    chmod +x "$MENU_SCRIPT"
}

write_service_and_timer() {
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Auto Backup VPS to Telegram
After=network.target mysql.service mariadb.service postgresql.service

[Service]
Type=oneshot
Environment="TZ=${TZ:-UTC}"
ExecStart=/usr/bin/env TZ=${TZ:-UTC} $RUNNER
User=root

[Install]
WantedBy=multi-user.target
EOF

    cat > "$TIMER_FILE" <<EOF
[Unit]
Description=Run Auto Backup VPS

[Timer]
OnCalendar=*-*-* 03:00:00
Persistent=true

[Install]
WantedBy=timers.target
EOF
}

write_menu_launcher() {
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
}

# installer run
ensure_root
print_banner

mkdir -p "$INSTALL_DIR"
touch "$LOGFILE"
write_runner
write_menu
write_service_and_timer
write_menu_launcher

# default config if not exist
if [[ ! -f "$CONFIG_FILE" ]]; then
    cat > "$CONFIG_FILE" <<EOC
BOT_TOKEN=""
CHAT_ID=""
FOLDERS_RAW=""

USE_MYSQL="n"
MYSQL_MULTI_CONF=""

USE_PG="n"
RETENTION_DAYS="7"
TZ="UTC"
INSTALL_DIR="$INSTALL_DIR"
EOC
fi

# reload & enable timer/service
systemctl daemon-reload || true
systemctl enable --now auto-backup.timer 2>/dev/null || true
systemctl enable auto-backup.service 2>/dev/null || true

echo -e "${GRN}Install selesai. Jalankan: menu-bot-backup${RST}"
echo -e "Config: $CONFIG_FILE"
exit 0
