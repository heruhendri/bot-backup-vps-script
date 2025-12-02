#!/bin/bash
set -euo pipefail
clear

WATERMARK_INSTALL="=== AUTO BACKUP VPS — INSTALLER ===
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

# Jika config ada → tanya update
if [[ -f "$CONFIG_FILE" ]]; then
    echo "[INFO] Config ditemukan: $CONFIG_FILE"
    read -p "Config sudah ada. Update config? (y/N): " RESP_UPD
    [[ "${RESP_UPD,,}" == "y" ]] && UPDATE_CONFIG="y" || UPDATE_CONFIG="n"
else
    UPDATE_CONFIG="y"
fi

# Input baru jika update_config=y
if [[ "$UPDATE_CONFIG" == "y" ]]; then
    echo ""
    read -p "Masukkan TOKEN Bot Telegram: " BOT_TOKEN
    read -p "Masukkan CHAT_ID Telegram: " CHAT_ID
    read -p "Masukkan folder yang mau di-backup (comma separated): " FOLDERS_RAW

    read -p "Backup MySQL? (y/n): " USE_MYSQL
    MYSQL_MULTI_CONF=""
    if [[ "$USE_MYSQL" == "y" ]]; then
        read -p "Berapa konfigurasi MySQL? " MYSQL_COUNT
        MYSQL_COUNT=${MYSQL_COUNT:-0}
        for ((i=1; i<=MYSQL_COUNT; i++)); do
            echo ""
            echo "📌 Konfigurasi MySQL ke-$i"
            read -p "MySQL Host (default: localhost): " MYSQL_HOST
            MYSQL_HOST=${MYSQL_HOST:-localhost}
            read -p "MySQL Username: " MYSQL_USER
            read -s -p "MySQL Password: " MYSQL_PASS
            echo ""
            echo "Mode backup database: 1) Semua  2) Pilih"
            read -p "Pilih (1/2): " MODE
            if [[ "$MODE" == "1" ]]; then
                DBLIST="all"
            else
                read -p "Masukkan daftar DB (comma separated): " DBLIST
            fi
            ENTRY="${MYSQL_USER}:${MYSQL_PASS}@${MYSQL_HOST}:${DBLIST}"
            [[ -z "$MYSQL_MULTI_CONF" ]] && MYSQL_MULTI_CONF="$ENTRY" || MYSQL_MULTI_CONF="${MYSQL_MULTI_CONF};${ENTRY}"
        done
    fi

    read -p "Backup PostgreSQL? (y/n): " USE_PG
    read -p "Retention days: " RETENTION_DAYS
    read -p "Timezone (ex: Asia/Jakarta): " TZ
    read -p "Jadwal OnCalendar (ex: *-*-* 03:00:00): " CRON_TIME

    timedatectl set-timezone "$TZ" || true

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
# ======================================================
#  Backup-Runner (HEREDOC LITERAL FIXED)
# ======================================================
cat > "$RUNNER" <<'BPR'
#!/bin/bash
set -euo pipefail

CONFIG_FILE="/opt/auto-backup/config.conf"
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
else
    echo "[ERROR] Config not found: $CONFIG_FILE"
    exit 1
fi

export TZ="${TZ:-UTC}"

BACKUP_DIR="${INSTALL_DIR}/backups"
mkdir -p "$BACKUP_DIR"

DATE=$(date +%F-%H%M)
FILE="$BACKUP_DIR/backup-$DATE.tar.gz"
TMP_DIR="${INSTALL_DIR}/tmp-$DATE"

mkdir -p "$TMP_DIR"

# Backup folders
IFS=',' read -r -a FOLDERS <<< "${FOLDERS_RAW:-}"
for f in "${FOLDERS[@]}"; do
    [[ -d "$f" ]] && cp -a "$f" "$TMP_DIR/" || true
done

# Backup MySQL Multi
if [[ "${USE_MYSQL:-n}" == "y" && -n "${MYSQL_MULTI_CONF:-}" ]]; then
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
            OUT="$TMP_DIR/mysql/${MYSQL_USER}@${MYSQL_HOST}_ALL.sql"
            mysqldump $MYSQL_ARGS --all-databases > "$OUT" 2>/dev/null || true
        else
            IFS=',' read -r -a DBARR <<< "$MYSQL_DB_LIST"
            for DB in "${DBARR[@]}"; do
                OUT="$TMP_DIR/mysql/${MYSQL_USER}@${MYSQL_HOST}_${DB}.sql"
                mysqldump $MYSQL_ARGS "$DB" > "$OUT" 2>/dev/null || true
            done
        fi
    done
fi

# Backup PostgreSQL
if [[ "${USE_PG:-n}" == "y" ]]; then
    mkdir -p "$TMP_DIR/postgres"
    if id -u postgres >/dev/null 2>&1; then
        su - postgres -c "pg_dumpall > $TMP_DIR/postgres/all.sql" || true
    fi
fi

tar -czf "$FILE" -C "$TMP_DIR" .

# Send to Telegram
if [[ -n "$BOT_TOKEN" && -n "$CHAT_ID" ]]; then
    curl -s -F document=@"$FILE" \
         -F caption="Backup selesai: $(basename "$FILE")" \
         "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument?chat_id=${CHAT_ID}" || true
fi

rm -rf "$TMP_DIR"

# Retensi
find "$BACKUP_DIR" -type f -mtime +"${RETENTION_DAYS}" -delete || true

echo "[OK] Backup done: $FILE"
BPR

chmod +x "$RUNNER"
echo "[OK] Backup runner dibuat."

# ======================================================
#  Buat systemd Service
# ======================================================
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Auto Backup VPS to Telegram
After=network.target mysql.service mariadb.service postgresql.service

[Service]
Type=oneshot
Environment="TZ=$TZ"
ExecStart=$RUNNER
User=root

[Install]
WantedBy=multi-user.target
EOF

# ======================================================
#  Buat systemd Timer
# ======================================================
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
echo "[OK] Systemd service & timer aktif."

# ======================================================
#  MENU PRO (FULL)
# ======================================================
cat > "$MENU_FILE" <<'MENU'
#!/bin/bash
set -euo pipefail

CONFIG="/opt/auto-backup/config.conf"
INSTALL_DIR="/opt/auto-backup"
RUNNER="$INSTALL_DIR/backup-runner.sh"
SERVICE="auto-backup.service"
TIMER="auto-backup.timer"

WATERMARK_HEADER="=== AUTO BACKUP VPS — MENU PRO ===
SCRIPT BY: HENDRI
SUPPORT: https://t.me/GbtTapiPngnSndiri
========================================"
WATERMARK_FOOTER="========================================
SCRIPT BY: HENDRI — AUTO BACKUP VPS
Support: https://t.me/GbtTapiPngnSndiri"

[[ ! -f "$CONFIG" ]] && echo "Config tidak ditemukan!" && exit 1

source "$CONFIG"

pause(){ read -p "Tekan ENTER untuk lanjut..."; }
confirm(){ read -p "$1 (y/N): " x; [[ "${x,,}" == "y" ]]; }
# =============================
#   Fungsi Status — MENU 19
# =============================
show_status() {
    echo -e "\e[36m$WATERMARK_HEADER\e[0m"
    echo ""

    GREEN="\e[32m"
    BLUE="\e[34m"
    RESET="\e[0m"

    # SERVICE
    svc_active=$(systemctl is-active "$SERVICE")
    svc_enabled=$(systemctl is-enabled "$SERVICE")
    echo "Service status : $svc_active (enabled: $svc_enabled)"

    # TIMER
    tm_active=$(systemctl is-active "$TIMER")
    tm_enabled=$(systemctl is-enabled "$TIMER")
    echo "Timer status   : $tm_active (enabled: $tm_enabled)"

    # ========================================
    #    NEXT RUN (paling akurat)
    # ========================================
    next_run=""
    row=$(systemctl list-timers --all | grep "$TIMER" | head -n1)

    if [[ -n "$row" ]]; then
        next_run=$(echo "$row" | awk '{print $1" "$2" "$3}')
    fi

    if [[ -z "$next_run" ]]; then
        epoch=$(systemctl show "$TIMER" -p NextElapseUSec --value)
        if [[ "$epoch" =~ ^[0-9]+$ ]] && ((epoch > 0)); then
            epoch=$((epoch/1000000))
            next_run=$(date -d @"$epoch" "+%Y-%m-%d %H:%M:%S")
        fi
    fi

    [[ -z "$next_run" ]] && next_run="(tidak tersedia)"

    echo -e "Next run       : ${BLUE}$next_run${RESET}"

    # ========================================
    #      TIME LEFT + PROGRESS
    # ========================================
    if [[ "$next_run" == "("* ]]; then
        echo "Time left      : (tidak tersedia)"
        echo "Progress       : (tidak tersedia)"
    else
        next_epoch=$(date -d "$next_run" +%s)
        now_epoch=$(date +%s)
        diff=$((next_epoch - now_epoch))

        if (( diff <= 0 )); then
            echo "Time left      : 0 detik"
            echo "Progress       : 100%"
        else
            d=$((diff/86400))
            h=$(((diff%86400)/3600))
            m=$(((diff%3600)/60))
            s=$((diff%60))

            left=""
            [[ $d -gt 0 ]] && left="$left$d hari "
            [[ $h -gt 0 ]] && left="$left$h jam "
            [[ $m -gt 0 ]] && left="$left$m menit "
            left="$left$s detik"

            echo -e "Time left      : ${GREEN}$left${RESET}"

            # ----- PROGRESS BAR -----

            last_epoch=$(journalctl -u "$SERVICE" --output=short-unix -n 50 \
                | awk '/Backup done/ {print $1; exit}' | cut -d'.' -f1)

            if [[ -z "$last_epoch" ]]; then
                echo "Progress       : (belum ada data)"
            else
                total=$((next_epoch - last_epoch))
                elapsed=$((now_epoch - last_epoch))

                (( total <= 0 )) && percent=100 || percent=$((elapsed * 100 / total))
                (( percent < 0 )) && percent=0
                (( percent > 100 )) && percent=100

                filled=$((percent/5))
                bar=""
                for ((i=1; i<=filled; i++)); do bar+="█"; done
                while (( ${#bar} < 20 )); do bar+=" "; done

                echo -e "Progress       : ${BLUE}[${bar}]${RESET} $percent%"
            fi
        fi
    fi

    # ========================================
    #   LAST BACKUP FILE
    # ========================================
    BACKUP_DIR="$INSTALL_DIR/backups"
    if [[ ! -d "$BACKUP_DIR" ]]; then
        echo "Last backup    : (directory tidak ditemukan)"
    else
        lastfile=$(ls -1t "$BACKUP_DIR" | head -n1)
        if [[ -z "$lastfile" ]]; then
            echo "Last backup    : (belum ada)"
        else
            t=$(stat -c '%y' "$BACKUP_DIR/$lastfile" | cut -d'.' -f1)
            echo -e "Last backup    : ${GREEN}$lastfile${RESET} ($t)"
        fi
    fi

    # ========================================
    #   LAST LOG
    # ========================================
    echo ""
    echo "--- Log terakhir ($SERVICE) ---"
    journalctl -u "$SERVICE" -n 5 --no-pager || echo "(log tidak ada)"

    echo ""
    echo -e "\e[36m$WATERMARK_FOOTER\e[0m"
    pause
}

# ================================
# SEKSIP MENU – PENGATURAN
# ================================
save_config(){
    cat > "$CONFIG" <<EOF
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
    chmod 600 "$CONFIG"
    echo "[OK] Config disimpan."
}

reload_systemd(){
    systemctl daemon-reload
    systemctl restart "$TIMER"
    systemctl restart "$SERVICE"
    echo "[OK] Service & Timer direstart."
}

add_folder(){
    read -p "Masukkan folder baru: " F
    [[ -z "$F" ]] && echo "Kosong." && return
    [[ -z "$FOLDERS_RAW" ]] && FOLDERS_RAW="$F" || FOLDERS_RAW="$FOLDERS_RAW,$F"
    echo "[OK] Folder ditambahkan."
}

delete_folder(){
    IFS=',' read -ra arr <<< "$FOLDERS_RAW"
    if (( ${#arr[@]} == 0 )); then echo "Tidak ada folder."; return; fi
    echo "Daftar folder:"
    for i in "${!arr[@]}"; do echo "$((i+1))) ${arr[$i]}"; done
    read -p "Hapus nomor: " n
    ((n<1 || n>${#arr[@]})) && echo "Invalid." && return
    unset 'arr[n-1]'
    FOLDERS_RAW=$(IFS=','; echo "${arr[*]}")
    echo "[OK] Folder dihapus."
}

# MySQL list/add/edit/delete
list_mysql(){
    [[ -z "$MYSQL_MULTI_CONF" ]] && echo "(tidak ada MySQL)" && return
    IFS=';' read -ra L <<< "$MYSQL_MULTI_CONF"
    for i in "${!L[@]}"; do echo "$((i+1))) ${L[$i]}"; done
}

add_mysql(){
    read -p "Host: " H
    H=${H:-localhost}
    read -p "User: " U
    read -s -p "Pass: " P; echo
    echo "Mode DB: 1) all  2) pilih"
    read -p "Pilih: " m
    if [[ "$m" == "1" ]]; then
        DB="all"
    else
        read -p "Daftar DB: " DB
    fi
    entry="${U}:${P}@${H}:${DB}"
    [[ -z "$MYSQL_MULTI_CONF" ]] && MYSQL_MULTI_CONF="$entry" || MYSQL_MULTI_CONF="$MYSQL_MULTI_CONF;$entry"
    echo "[OK] MySQL ditambah."
}

edit_mysql(){
    IFS=';' read -ra L <<< "$MYSQL_MULTI_CONF"
    for i in "${!L[@]}"; do echo "$((i+1))) ${L[$i]}"; done
    read -p "Edit nomor: " n
    ((n<1 || n>${#L[@]})) && echo "Invalid." && return

    old="${L[n-1]}"
    OU=$(echo "$old" | cut -d':' -f1)
    OP=$(echo "$old" | cut -d':' -f2 | cut -d'@' -f1)
    OH=$(echo "$old" | cut -d'@' -f2 | cut -d':' -f1)
    OD=$(echo "$old" | rev | cut -d: -f1 | rev)

    read -p "Host [$OH]: " H; H=${H:-$OH}
    read -p "User [$OU]: " U; U=${U:-$OU}
    read -s -p "Pass (kosong=old): " P; echo; [[ -z "$P" ]] && P="$OP"
    read -p "DB [$OD]: " D; D=${D:-$OD}

    L[n-1]="${U}:${P}@${H}:${D}"
    MYSQL_MULTI_CONF=$(IFS=';'; echo "${L[*]}")
    echo "[OK] MySQL diperbarui."
}

delete_mysql(){
    IFS=';' read -ra L <<< "$MYSQL_MULTI_CONF"
    for i in "${!L[@]}"; do echo "$((i+1))) ${L[$i]}"; done
    read -p "Hapus nomor: " n
    ((n<1 || n>${#L[@]})) && echo "Invalid." && return
    unset 'L[n-1]'
    MYSQL_MULTI_CONF=$(IFS=';'; echo "${L[*]}")
    echo "[OK] MySQL dihapus."
}

edit_pg(){
    read -p "Backup PostgreSQL? (y/n) [$USE_PG]: " a
    [[ -n "$a" ]] && USE_PG="$a"
    echo "[OK] PG updated ke: $USE_PG"
}

list_backups(){
    ls -1t "$INSTALL_DIR/backups" 2>/dev/null || echo "(tidak ada)"
}

restore_backup(){
    echo "Daftar backup:"
    mapfile -t FL < <(ls -1t "$INSTALL_DIR/backups" 2>/dev/null)
    (( ${#FL[@]} == 0 )) && echo "Tidak ada file." && return
    for i in "${!FL[@]}"; do echo "$((i+1))) ${FL[$i]}"; done
    read -p "Restore nomor: " n
    ((n<1 || n>${#FL[@]})) && echo "Invalid." && return
    file="${INSTALL_DIR}/backups/${FL[n-1]}"
    TMP="/opt/auto-backup/restore-$(date +%s)"
    mkdir -p "$TMP"
    tar -xzf "$file" -C "$TMP"
    echo "File diekstrak di: $TMP"
    if confirm "Terapkan ke / ? (RISKY)"; then
        rsync -a "$TMP"/ /
        echo "[OK] Restore selesai."
    fi
    rm -rf "$TMP"
}

rebuild_installer(){
    echo "[OK] Rebuilding installer files..."
    systemctl daemon-reload
    systemctl restart "$TIMER"
    systemctl restart "$SERVICE"
}

encrypt_last_backup(){
    LAST=$(ls -1t "$INSTALL_DIR/backups" | head -n1)
    [[ -z "$LAST" ]] && echo "Tidak ada backup." && return
    read -s -p "Password zip: " P; echo
    OUT="${INSTALL_DIR}/backups/${LAST%.*}.zip"
    zip -P "$P" "$OUT" "$INSTALL_DIR/backups/$LAST"
    echo "[OK] Backup terenkripsi: $OUT"
}

test_backup(){
    bash "$RUNNER"
    echo "[OK] Backup test selesai."
}

# ===============================
#         MAIN MENU
# ===============================
while true; do
    clear
    echo "$WATERMARK_HEADER"
    echo ""
    echo "=============================================="
    echo "   AUTO BACKUP — MENU PRO (Telegram VPS)"
    echo "=============================================="
    echo "1) Lihat konfigurasi"
    echo "2) Edit BOT TOKEN"
    echo "3) Edit CHAT ID"
    echo "4) Tambah folder backup"
    echo "5) Hapus folder backup"
    echo "6) Tambah Konfigurasi MySQL"
    echo "7) Edit Konfigurasi MySQL"
    echo "8) Hapus Konfigurasi MySQL"
    echo "9) Edit PostgreSQL settings"
    echo "10) Ubah timezone"
    echo "11) Ubah retention"
    echo "12) Ubah jadwal backup (OnCalendar)"
    echo "13) Test backup sekarang"
    echo "14) Restore backup"
    echo "15) Rebuild installer"
    echo "16) Encrypt latest backup"
    echo "17) Restart service & timer"
    echo "18) Simpan config"
    echo "19) STATUS (service/last/next/progress)"
    echo "0) Keluar"
    echo "----------------------------------------------"
    read -p "Pilih menu: " x

    case "$x" in
        1) cat "$CONFIG"; pause ;;
        2) read -p "BOT TOKEN baru: " BOT_TOKEN ;;
        3) read -p "CHAT ID baru: " CHAT_ID ;;
        4) add_folder ;;
        5) delete_folder ;;
        6) add_mysql ;;
        7) edit_mysql ;;
        8) delete_mysql ;;
        9) edit_pg ;;
        10) read -p "Timezone baru: " TZ; timedatectl set-timezone "$TZ" ;;
        11) read -p "Retention baru: " RETENTION_DAYS ;;
        12) read -p "Masukkan OnCalendar baru: " CRON_TIME ;;
        13) test_backup ;;
        14) restore_backup ;;
        15) rebuild_installer ;;
        16) encrypt_last_backup ;;
        17) reload_systemd ;;
        18) save_config ;;
        19) show_status ;;
        0) exit 0 ;;
        *) echo "Pilihan invalid."; sleep 1 ;;
    esac
done

MENU

chmod +x "$MENU_FILE"
ln -sf "$MENU_FILE" /usr/bin/menu-bot-backup
chmod +x /usr/bin/menu-bot-backup

echo "[OK] MENU PRO terinstall sebagai: menu-bot-backup"
echo ""
echo "$WATERMARK_END"
echo ""
echo "[INFO] Menjalankan backup pertama..."
bash "$RUNNER" || true
echo ""
echo "Selesai. Ketik: menu-bot-backup"
