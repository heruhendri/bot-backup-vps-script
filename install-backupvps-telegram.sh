#!/bin/bash
set -uo pipefail
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

# If config exists, ask whether to update
if [[ -f "$CONFIG_FILE" ]]; then
    echo "[INFO] Config ditemukan: $CONFIG_FILE"
    read -p "Config sudah ada. Update config dan lanjut installer? (y/N): " RESP_UPD
    RESP_UPD=${RESP_UPD:-n}
    if [[ "$RESP_UPD" =~ ^[Yy]$ ]]; then
        UPDATE_CONFIG="y"
    else
        UPDATE_CONFIG="n"
    fi
else
    UPDATE_CONFIG="y"
fi

# If updating or no config, ask for inputs. If not updating, load existing.
if [[ "$UPDATE_CONFIG" == "y" ]]; then
    echo ""
    # ======================================================
    # Basic inputs
    # ======================================================
    read -p "Masukkan TOKEN Bot Telegram: " BOT_TOKEN
    read -p "Masukkan CHAT_ID Telegram: " CHAT_ID
    read -p "Masukkan folder yang mau di-backup (comma separated, contoh: /etc,/var/www): " FOLDERS_RAW

    read -p "Backup MySQL? (y/n): " USE_MYSQL
    MYSQL_MULTI_CONF=""
    if [[ "$USE_MYSQL" == "y" ]]; then
        echo ""
        read -p "Berapa konfigurasi MySQL yang ingin Anda tambahkan? " MYSQL_COUNT
        MYSQL_COUNT=${MYSQL_COUNT:-0}
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
    else
        MYSQL_MULTI_CONF=""
    fi

    # ------------------ MongoDB ------------------
    read -p "Backup MongoDB? (y/n): " USE_MONGO
    MONGO_MULTI_CONF=""
    if [[ "$USE_MONGO" == "y" ]]; then
        echo ""
        read -p "Berapa konfigurasi MongoDB yang ingin Anda tambahkan? " MONGO_COUNT
        MONGO_COUNT=${MONGO_COUNT:-0}
        for ((i=1; i<=MONGO_COUNT; i++)); do
            echo ""
            echo "📌 Konfigurasi MongoDB ke-$i"
            read -p "Mongo Host (default: localhost): " MONGO_HOST
            MONGO_HOST=${MONGO_HOST:-localhost}
            read -p "Mongo Port (default: 27017): " MONGO_PORT
            MONGO_PORT=${MONGO_PORT:-27017}
            read -p "Mongo Username (kosong jika tidak pakai auth): " MONGO_USER
            if [[ -n "$MONGO_USER" ]]; then
                read -s -p "Mongo Password: " MONGO_PASS
                echo ""
                read -p "Authentication DB (default: admin): " MONGO_AUTHDB
                MONGO_AUTHDB=${MONGO_AUTHDB:-admin}
            else
                MONGO_PASS=""
                MONGO_AUTHDB=""
            fi
            echo "Mode backup database:"
            echo "1) Backup SEMUA database"
            echo "2) Pilih database tertentu"
            read -p "Pilih (1/2): " MODE
            if [[ "$MODE" == "1" ]]; then
                MDBLIST="all"
            else
                read -p "Masukkan daftar DB (comma separated, ex: db1,db2): " MDBLIST
            fi
            # Entry format: user:pass@host:port:authdb:dbs
            ENTRY="${MONGO_USER}:${MONGO_PASS}@${MONGO_HOST}:${MONGO_PORT}:${MONGO_AUTHDB}:${MDBLIST}"
            if [[ -z "$MONGO_MULTI_CONF" ]]; then
                MONGO_MULTI_CONF="$ENTRY"
            else
                MONGO_MULTI_CONF="${MONGO_MULTI_CONF};${ENTRY}"
            fi
        done
    else
        MONGO_MULTI_CONF=""
    fi
    # ------------------ end MongoDB ------------------

    read -p "Backup PostgreSQL? (y/n): " USE_PG
    read -p "Retention (berapa hari file backup disimpan): " RETENTION_DAYS
    read -p "Timezone (contoh: Asia/Jakarta): " TZ
    read -p "Jadwal cron (format systemd timer, contoh: *-*-* 03:00:00): " CRON_TIME

    echo ""
    echo "[OK] Setting timezone sistem => $TZ"
    timedatectl set-timezone "$TZ" || echo "[WARN] timedatectl set-timezone mungkin gagal jika tidak dijalankan sebagai root"

    # Write config (secure)
    cat > "$CONFIG_FILE" <<EOF
BOT_TOKEN="$BOT_TOKEN"
CHAT_ID="$CHAT_ID"
FOLDERS_RAW="$FOLDERS_RAW"

USE_MYSQL="$USE_MYSQL"
MYSQL_MULTI_CONF="$MYSQL_MULTI_CONF"

USE_MONGO="$USE_MONGO"
MONGO_MULTI_CONF="$MONGO_MULTI_CONF"

USE_PG="$USE_PG"
RETENTION_DAYS="$RETENTION_DAYS"
TZ="$TZ"
INSTALL_DIR="$INSTALL_DIR"
EOF

    chmod 600 "$CONFIG_FILE"
    echo "[OK] Config saved: $CONFIG_FILE"
else
    # load existing config for installer to use
    echo "[INFO] Menggunakan config yang sudah ada: $CONFIG_FILE"
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
    # ensure defaults exist
    FOLDERS_RAW=${FOLDERS_RAW:-""}
    MYSQL_MULTI_CONF=${MYSQL_MULTI_CONF:-""}
    MONGO_MULTI_CONF=${MONGO_MULTI_CONF:-""}
    RETENTION_DAYS=${RETENTION_DAYS:-30}
    TZ=${TZ:-UTC}
    CRON_TIME=${CRON_TIME:-"*-*-* 03:00:00"}
fi

# ======================================================
# Create backup-runner (safe literal - won't expand now)
# ======================================================
cat > "$RUNNER" <<'BPR'
#!/bin/bash
set -euo pipefail

CONFIG_FILE="/opt/auto-backup/config.conf"
if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
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

# Set waktu mulai durasi backup
START_TIME=$(date +%s)

# backup folders
IFS=',' read -r -a FOLDERS <<< "${FOLDERS_RAW:-}"
for f in "${FOLDERS[@]}"; do
    if [[ -d "$f" ]]; then
        cp -a "$f" "$TMP_DIR/" || true
    fi
done

# backup mysql
if [[ "${USE_MYSQL:-n}" == "y" && ! -z "${MYSQL_MULTI_CONF:-}" ]]; then
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

# backup mongo
if [[ "${USE_MONGO:-n}" == "y" && ! -z "${MONGO_MULTI_CONF:-}" ]]; then
    mkdir -p "$TMP_DIR/mongo"
    IFS=';' read -r -a MONGO_ITEMS <<< "$MONGO_MULTI_CONF"
    for ITEM in "${MONGO_ITEMS[@]}"; do
        # format: user:pass@host:port:authdb:dbs
        CREDS=$(echo "$ITEM" | cut -d'@' -f1)
        HOSTPART=$(echo "$ITEM" | cut -d'@' -f2)
        MONGO_USER=$(echo "$CREDS" | cut -d':' -f1)
        MONGO_PASS=$(echo "$CREDS" | cut -d':' -f2)
        MONGO_HOST=$(echo "$HOSTPART" | cut -d':' -f1)
        MONGO_PORT=$(echo "$HOSTPART" | cut -d':' -f2)
        MONGO_AUTHDB=$(echo "$HOSTPART" | cut -d':' -f3)
        MONGO_DB_LIST=$(echo "$HOSTPART" | cut -d':' -f4)

        # build target subdir name safe
        SAFE_NAME=$(echo "${MONGO_USER}_${MONGO_HOST}_${MONGO_PORT}" | sed 's/[^a-zA-Z0-9._-]/_/g')
        DEST_DIR="$TMP_DIR/mongo/$SAFE_NAME"
        mkdir -p "$DEST_DIR"

        # check mongodump
        if ! command -v mongodump >/dev/null 2>&1; then
            echo "[WARN] mongodump not found; skip mongo dump for $MONGO_HOST:$MONGO_PORT"
            continue
        fi

        # build base args
        BASE="--host=${MONGO_HOST} --port=${MONGO_PORT} --out=${DEST_DIR}"
        if [[ -n "$MONGO_USER" ]]; then
            BASE="$BASE --username=${MONGO_USER} --password='${MONGO_PASS}' --authenticationDatabase=${MONGO_AUTHDB}"
        fi

        if [[ "$MONGO_DB_LIST" == "all" ]]; then
            # dump all (mongodump without --db dumps all DBs)
            # note: mongodump default dumps all if no --db specified
            eval mongodump $BASE || true
        else
            IFS=',' read -r -a MDBARR <<< "$MONGO_DB_LIST"
            for MDB in "${MDBARR[@]}"; do
                eval mongodump $BASE --db="${MDB}" || true
            done
        fi

        # compress this mongo dump dir into tar.gz
        if [[ -d "$DEST_DIR" ]]; then
            tar -czf "${DEST_DIR}.tar.gz" -C "$DEST_DIR" . || true
            rm -rf "$DEST_DIR"
        fi
    done
fi

# backup postgres
if [[ "${USE_PG:-n}" == "y" ]]; then
    mkdir -p "$TMP_DIR/postgres"
    if id -u postgres >/dev/null 2>&1; then
        su - postgres -c "pg_dumpall > $TMP_DIR/postgres/all.sql" || true
    else
        echo "[WARN] User 'postgres' not found or pg_dumpall unavailable"
    fi
fi

tar -czf "$FILE" -C "$TMP_DIR" . || (echo "[ERROR] tar failed"; exit 1)



# Hitung durasi & info file
END_TIME=$(date +%s)
DURATION=$(( END_TIME - START_TIME ))
FILE_SIZE=$(du -h "$FILE" | awk '{print $1}')

# Ambil nama VPS
VPS_NAME=$(hostname 2>/dev/null || echo "Unknown-VPS")

# Buat caption dengan emoji (NON-MARKDOWN, aman)
CAPTION="📦 Backup Selesai

🖥 VPS: ${VPS_NAME}
📅 Tanggal: $(date '+%Y-%m-%d %H:%M:%S')
⏱ Durasi: ${DURATION} detik
📁 Ukuran File: ${FILE_SIZE}
📄 Nama File: $(basename "$FILE")"

# Kirim ke Telegram
if [[ -n "${BOT_TOKEN:-}" && -n "${CHAT_ID:-}" ]]; then
    curl -s -F document=@"$FILE" \
         -F caption="$CAPTION" \
         "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument?chat_id=${CHAT_ID}" || true
else
    echo "[WARN] BOT_TOKEN/CHAT_ID kosong; melewatkan kirim ke Telegram"
fi




# cleanup temp
rm -rf "$TMP_DIR"

# retention
if [[ -n "${RETENTION_DAYS:-}" ]]; then
    find "$BACKUP_DIR" -type f -mtime +"${RETENTION_DAYS}" -delete || true
fi

echo "[OK] Backup done: $FILE"
BPR

chmod +x "$RUNNER"
echo "[OK] Backup runner created: $RUNNER"

# ======================================================
# Create systemd service & timer
# ======================================================
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Auto Backup VPS to Telegram
After=network.target mysql.service mariadb.service postgresql.service mongodb.service

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

systemctl daemon-reload || true
systemctl enable auto-backup.service || true
systemctl enable --now auto-backup.timer || true

echo "[OK] systemd service & timer configured."

# ======================================================
# Install menu (menu PRO — full content based on your menu)
# with watermark header+footer and menu status option
# ======================================================
cat > "$MENU_FILE" <<'MENU'
#!/bin/bash
set -euo pipefail

# PRO Menu for Auto Backup VPS — TELEGRAM BOT
# Location expected: /opt/auto-backup/menu.sh

CONFIG="/opt/auto-backup/config.conf"
INSTALL_DIR="/opt/auto-backup"
RUNNER="$INSTALL_DIR/backup-runner.sh"
SERVICE_FILE="/etc/systemd/system/auto-backup.service"
TIMER_FILE="/etc/systemd/system/auto-backup.timer"
LOGFILE="$INSTALL_DIR/menu-pro.log"

WATERMARK_HEADER="=== AUTO BACKUP VPS — MENU PRO ===
SCRIPT BY: HENDRI
SUPPORT: https://t.me/GbtTapiPngnSndiri
========================================"
WATERMARK_FOOTER="========================================
SCRIPT BY: HENDRI — AUTO BACKUP VPS
Support: https://t.me/GbtTapiPngnSndiri"

if [[ ! -f "$CONFIG" ]]; then
    echo "Config tidak ditemukan di $CONFIG. Jalankan installer terlebih dahulu." | tee -a "$LOGFILE"
    exit 1
fi

# load config
# shellcheck source=/dev/null
source "$CONFIG"
# Prevent unbound variable crash
BOT_TOKEN="${BOT_TOKEN:-}"
CHAT_ID="${CHAT_ID:-}"
FOLDERS_RAW="${FOLDERS_RAW:-}"
USE_MYSQL="${USE_MYSQL:-n}"
MYSQL_MULTI_CONF="${MYSQL_MULTI_CONF:-}"
USE_MONGO="${USE_MONGO:-n}"
MONGO_MULTI_CONF="${MONGO_MULTI_CONF:-}"
USE_PG="${USE_PG:-n}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
TZ="${TZ:-Asia/Jakarta}"
INSTALL_DIR="${INSTALL_DIR:-/opt/auto-backup}"

save_config() {
    cat <<EOF > "$CONFIG"
BOT_TOKEN="$BOT_TOKEN"
CHAT_ID="$CHAT_ID"
FOLDERS_RAW="$FOLDERS_RAW"

USE_MYSQL="$USE_MYSQL"
MYSQL_MULTI_CONF="$MYSQL_MULTI_CONF"

USE_MONGO="$USE_MONGO"
MONGO_MULTI_CONF="$MONGO_MULTI_CONF"

USE_PG="$USE_PG"
RETENTION_DAYS="$RETENTION_DAYS"
TZ="$TZ"
INSTALL_DIR="$INSTALL_DIR"
EOF
    chmod 600 "$CONFIG"
    echo "[$(date '+%F %T')] Config saved." >> "$LOGFILE"
}

reload_systemd() {
    systemctl daemon-reload
    systemctl restart auto-backup.timer 2>/dev/null || true
    systemctl restart auto-backup.service 2>/dev/null || true
    echo "[$(date '+%F %T')] Systemd reloaded & services restarted." >> "$LOGFILE"
}

pause() {
    read -p "Tekan ENTER untuk lanjut..."
}

confirm() {
    local msg="$1"
    read -p "$msg (y/N): " ans
    case "$ans" in
        y|Y) return 0 ;;
        *) return 1 ;;
    esac
}




# ---------- Status Menu ----------
show_status() {
    clear
    echo "$WATERMARK_HEADER"
    echo ""
    echo "=== STATUS BACKUP — STATIC ==="
    echo ""

    svc_active=$(systemctl is-active auto-backup.service 2>/dev/null || echo "unknown")
    svc_enabled=$(systemctl is-enabled auto-backup.service 2>/dev/null || echo "unknown")
    echo "Service status : $svc_active (enabled: $svc_enabled)"

    tm_active=$(systemctl is-active auto-backup.timer 2>/dev/null || echo "unknown")
    tm_enabled=$(systemctl is-enabled auto-backup.timer 2>/dev/null || echo "unknown")
    echo "Timer status   : $tm_active (enabled: $tm_enabled)"

    next_run=$(systemctl list-timers --all | grep auto-backup.timer | awk '{print $1, $2, $3}')
    [[ -z "$next_run" ]] && next_run="(tidak tersedia)"
    echo "Next run       : $next_run"

    BACKUP_DIR="$INSTALL_DIR/backups"
    lastfile=$(ls -1t "$BACKUP_DIR" 2>/dev/null | head -n1)
    if [[ -n "$lastfile" ]]; then
        lasttime=$(stat -c '%y' "$BACKUP_DIR/$lastfile" | cut -d'.' -f1)
        echo "Last backup    : $lastfile ($lasttime)"
    else
        echo "Last backup    : (belum ada)"
    fi

    echo ""
    echo "--- Log (5 baris terakhir) ---"
    journalctl -u auto-backup.service -n 5 --no-pager

    echo ""
    read -p "Tekan ENTER untuk kembali..."
}

# -------- Show Status Live (fixed auto-refresh) ----------
show_status_live() {
    trap 'tput cnorm; stty sane; clear; echo "Keluar dari mode realtime."; return 0' SIGINT SIGTERM
    tput civis 2>/dev/null || true

    while true; do
        clear
        echo -e "\e[36m$WATERMARK_HEADER\e[0m"
        echo "        STATUS BACKUP — REALTIME (Refresh 1 detik)"
        echo ""

        GREEN="\e[32m"
        BLUE="\e[34m"
        RESET="\e[0m"

        svc_active=$(systemctl is-active auto-backup.service 2>/dev/null || echo "unknown")
        svc_enabled=$(systemctl is-enabled auto-backup.service 2>/dev/null || echo "unknown")
        echo "Service status : $svc_active (enabled: $svc_enabled)"

        tm_active=$(systemctl is-active auto-backup.timer 2>/dev/null || echo "unknown")
        tm_enabled=$(systemctl is-enabled auto-backup.timer 2>/dev/null || echo "unknown")
        echo "Timer status   : $tm_active (enabled: $tm_enabled)"

        line=$(systemctl list-timers --all 2>/dev/null | grep auto-backup.timer | head -n1 || true)
        if [[ -n "$line" ]]; then
            nr1=$(echo "$line" | awk '{print $1}')
            nr2=$(echo "$line" | awk '{print $2}')
            nr3=$(echo "$line" | awk '{print $3}')
            next_run="$nr1 $nr2 $nr3"
        else
            next_run="(tidak tersedia)"
        fi
        echo -e "Next run       : ${BLUE}$next_run${RESET}"

        if [[ "$next_run" =~ ^\( ]]; then
            echo "Time left      : (tidak tersedia)"
            echo "Progress       : (tidak tersedia)"
        else
            next_epoch=0
            if ! next_epoch=$(date -d "$next_run" +%s 2>/dev/null); then
                next_epoch=0
            fi
            now_epoch=$(date +%s)
            diff=$(( next_epoch - now_epoch ))

            if (( next_epoch == 0 || diff <= 0 )); then
                echo "Time left      : 0 detik"
                echo "Progress       : 100%"
            else
                d=$(( diff/86400 ))
                h=$(( (diff%86400)/3600 ))
                m=$(( (diff%3600)/60 ))
                s=$(( diff%60 ))
                echo "Time left      : $d hari $h jam $m menit $s detik"

last_epoch=$(awk '/\[BACKUP_DONE\]/ {print $2}' /var/log/auto-backup.log | tail -n1)


                if [[ -z "$last_epoch" || "$last_epoch" -eq 0 ]]; then
                    echo "Progress       : (tidak tersedia)"
                else
                    total_interval=$(( next_epoch - last_epoch ))
                    elapsed=$(( now_epoch - last_epoch ))

                    if (( total_interval <= 0 )); then
                        percent=100
                    else
                        percent=$(( elapsed * 100 / total_interval ))
                    fi

                    ((percent < 0)) && percent=0
                    ((percent > 100)) && percent=100

                    bars=$(( percent / 5 ))
                    bar=""
                    for ((i=1;i<=bars;i++)); do bar+="█"; done
                    while (( ${#bar} < 20 )); do bar+=" "; done

                    echo -e "Progress       : ${BLUE}[${bar}]${RESET} $percent%"
                fi
            fi
        fi

        BACKUP_DIR="$INSTALL_DIR/backups"
        lastfile=$(ls -1t "$BACKUP_DIR" 2>/dev/null | head -n1 || true)
        if [[ -z "$lastfile" ]]; then
            echo "Last backup    : (belum ada)"
        else
            lasttime=$(stat -c '%y' "$BACKUP_DIR/$lastfile" | cut -d'.' -f1)
            echo -e "Last backup    : ${GREEN}$lastfile${RESET} ($lasttime)"
        fi

        echo ""
        echo "--- Log auto-backup.service (3 baris terakhir) ---"
        journalctl -u auto-backup.service -n 3 --no-pager 2>/dev/null || echo "(log tidak tersedia)"

        echo ""
        echo "[Tekan CTRL+C untuk keluar realtime]"
        sleep 1 || true
    done

    tput cnorm 2>/dev/null || true
}

# ---------- Folder / MySQL / PG / Mongo functions ----------
add_folder() {
    read -p "Masukkan folder baru (single path, atau comma separated): " NEW_FOLDER
    if [[ -z "$NEW_FOLDER" ]]; then
        echo "Tidak ada input."
        return
    fi
    if [[ -z "$FOLDERS_RAW" ]]; then
        FOLDERS_RAW="$NEW_FOLDER"
    else
        FOLDERS_RAW="$FOLDERS_RAW,$NEW_FOLDER"
    fi
    echo "[OK] Folder tambahan disiapkan."
}

delete_folder() {
    if [[ -z "$FOLDERS_RAW" ]]; then
        echo "Tidak ada folder yang bisa dihapus."
        return
    fi
    IFS=',' read -ra FL <<< "$FOLDERS_RAW"
    echo "Daftar folder:"
    for i in "${!FL[@]}"; do
        printf "%2d) %s\n" $((i+1)) "${FL[$i]}"
    done
    read -p "Masukkan nomor yang ingin dihapus: " NUM
    if ! [[ "$NUM" =~ ^[0-9]+$ ]] || (( NUM < 1 || NUM > ${#FL[@]} )); then
        echo "Pilihan tidak valid."
        return
    fi
    unset 'FL[NUM-1]'
    FOLDERS_RAW=$(IFS=','; echo "${FL[*]}")
    echo "[OK] Folder dihapus."
}

# MySQL handlers (unchanged from before)
list_mysql() {
    if [[ -z "$MYSQL_MULTI_CONF" ]]; then
        echo "(tidak ada konfigurasi MySQL)"
        return
    fi
    IFS=';' read -ra LIST <<< "$MYSQL_MULTI_CONF"
    i=1
    for item in "${LIST[@]}"; do
        echo "[$i] $item"
        ((i++))
    done
}

add_mysql() {
    echo "Tambah konfigurasi MySQL baru:"
    read -p "MySQL Host (default: localhost): " MYSQL_HOST
    MYSQL_HOST=${MYSQL_HOST:-localhost}
    read -p "MySQL Username: " MYSQL_USER
    read -s -p "MySQL Password: " MYSQL_PASS
    echo ""
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
    echo "Konfigurasi lama: $OLD"
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

# -------- Mongo handlers (new) ----------
list_mongo() {
    if [[ -z "$MONGO_MULTI_CONF" ]]; then
        echo "(tidak ada konfigurasi MongoDB)"
        return
    fi
    IFS=';' read -ra LIST <<< "$MONGO_MULTI_CONF"
    i=1
    for item in "${LIST[@]}"; do
        echo "[$i] $item"
        ((i++))
    done
}

add_mongo() {
    echo "Tambah konfigurasi MongoDB baru:"
    read -p "Mongo Host (default: localhost): " MONGO_HOST
    MONGO_HOST=${MONGO_HOST:-localhost}
    read -p "Mongo Port (default: 27017): " MONGO_PORT
    MONGO_PORT=${MONGO_PORT:-27017}
    read -p "Mongo Username (kosong jika tidak pakai auth): " MONGO_USER
    if [[ -n "$MONGO_USER" ]]; then
        read -s -p "Mongo Password: " MONGO_PASS
        echo ""
        read -p "Authentication DB (default: admin): " MONGO_AUTHDB
        MONGO_AUTHDB=${MONGO_AUTHDB:-admin}
    else
        MONGO_PASS=""
        MONGO_AUTHDB=""
    fi
    echo "Mode database: 1) Semua  2) Pilih"
    read -p "Pilih: " MODE
    if [[ "$MODE" == "1" ]]; then MDBLIST="all"; else read -p "Masukkan nama database (comma separated): " MDBLIST; fi
    NEW_ENTRY="${MONGO_USER}:${MONGO_PASS}@${MONGO_HOST}:${MONGO_PORT}:${MONGO_AUTHDB}:${MDBLIST}"
    if [[ -z "$MONGO_MULTI_CONF" ]]; then MONGO_MULTI_CONF="$NEW_ENTRY"; else MONGO_MULTI_CONF="$MONGO_MULTI_CONF;$NEW_ENTRY"; fi
    echo "[OK] Ditambahkan."
}

edit_mongo() {
    if [[ -z "$MONGO_MULTI_CONF" ]]; then echo "Tidak ada konfigurasi MongoDB."; return; fi
    IFS=';' read -ra LIST <<< "$MONGO_MULTI_CONF"
    for i in "${!LIST[@]}"; do printf "%2d) %s\n" $((i+1)) "${LIST[$i]}"; done
    read -p "Pilih nomor untuk diedit: " NUM
    if ! [[ "$NUM" =~ ^[0-9]+$ ]] || (( NUM < 1 || NUM > ${#LIST[@]} )); then echo "Pilihan invalid."; return; fi
    IDX=$((NUM-1))
    OLD="${LIST[$IDX]}"
    echo "Konfigurasi lama: $OLD"
    OLD_USER=$(echo "$OLD" | cut -d':' -f1)
    OLD_PASS=$(echo "$OLD" | cut -d':' -f2 | cut -d'@' -f1)
    OLD_HOST=$(echo "$OLD" | cut -d'@' -f2 | cut -d':' -f1)
    OLD_PORT=$(echo "$OLD" | cut -d'@' -f2 | cut -d':' -f2)
    OLD_AUTHDB=$(echo "$OLD" | cut -d'@' -f2 | cut -d':' -f3)
    OLD_DB=$(echo "$OLD" | rev | cut -d: -f1 | rev)
    read -p "Mongo Host [$OLD_HOST]: " MONGO_HOST; MONGO_HOST=${MONGO_HOST:-$OLD_HOST}
    read -p "Mongo Port [$OLD_PORT]: " MONGO_PORT; MONGO_PORT=${MONGO_PORT:-$OLD_PORT}
    read -p "Mongo Username [$OLD_USER]: " MONGO_USER; MONGO_USER=${MONGO_USER:-$OLD_USER}
    read -s -p "Mongo Password (kosong = tetap): " MONGO_PASS; echo ""
    if [[ -z "$MONGO_PASS" ]]; then MONGO_PASS="$OLD_PASS"; fi
    read -p "Authentication DB [$OLD_AUTHDB]: " MONGO_AUTHDB; MONGO_AUTHDB=${MONGO_AUTHDB:-$OLD_AUTHDB}
    read -p "Database (comma or 'all') [$OLD_DB]: " MDBLIST; MDBLIST=${MDBLIST:-$OLD_DB}
    NEW_ENTRY="${MONGO_USER}:${MONGO_PASS}@${MONGO_HOST}:${MONGO_PORT}:${MONGO_AUTHDB}:${MDBLIST}"
    LIST[$IDX]="$NEW_ENTRY"
    MONGO_MULTI_CONF=$(IFS=';'; echo "${LIST[*]}")
    echo "[OK] Konfigurasi MongoDB diperbarui."
}

delete_mongo() {
    if [[ -z "$MONGO_MULTI_CONF" ]]; then echo "Tidak ada konfigurasi MongoDB."; return; fi
    IFS=';' read -ra LIST <<< "$MONGO_MULTI_CONF"
    for i in "${!LIST[@]}"; do printf "%2d) %s\n" $((i+1)) "${LIST[$i]}"; done
    read -p "Pilih nomor yang ingin dihapus: " NUM
    if ! [[ "$NUM" =~ ^[0-9]+$ ]] || (( NUM < 1 || NUM > ${#LIST[@]} )); then echo "Pilihan invalid."; return; fi
    unset 'LIST[NUM-1]'
    MONGO_MULTI_CONF=$(IFS=';'; echo "${LIST[*]}")
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

list_backups() {
    mkdir -p "$INSTALL_DIR/backups"
    ls -1tr "$INSTALL_DIR/backups" 2>/dev/null || echo "(tidak ada file backup)"
}

restore_backup() {
    echo "Daftar file backup (urut waktu):"
    files=()
    idx=1
    while IFS= read -r -d $'\0' f; do
        files+=("$f")
    done < <(find "$INSTALL_DIR/backups" -maxdepth 1 -type f -print0 | sort -z)
    if (( ${#files[@]} == 0 )); then echo "Tidak ada file backup." ; return; fi
    for i in "${!files[@]}"; do printf "%2d) %s\n" $((i+1)) "$(basename "${files[$i]}")"; done
    read -p "Pilih nomor file untuk restore: " NUM
    if ! [[ "$NUM" =~ ^[0-9]+$ ]] || (( NUM < 1 || NUM > ${#files[@]} )); then echo "Pilihan invalid."; return; fi
    SELECT="${files[$((NUM-1))]}"
    echo "File dipilih: $SELECT"
    echo "Isi file (preview):"
    tar -tzf "$SELECT" | sed -n '1,30p'
    if ! confirm "Lanjut restore dan timpa file sesuai archive ke root (/)? Pastikan backup cocok."; then
        echo "Restore dibatalkan."
        return
    fi
    TMPREST="$INSTALL_DIR/restore_tmp_$(date +%s)"
    mkdir -p "$TMPREST"
    tar -xzf "$SELECT" -C "$TMPREST"
    echo "File diekstrak ke $TMPREST"
    if confirm "Ekstrak ke / (akan menimpa file yang ada). Lanjut?"; then
        rsync -a --delete "$TMPREST"/ /
        echo "[OK] Restore selesai, files disalin ke /"
        echo "[$(date '+%F %T')] Restore from $(basename "$SELECT")" >> "$LOGFILE"
    else
        echo "Restore dibatalkan. Menghapus temp..."
    fi
    rm -rf "$TMPREST"
}

rebuild_installer_files() {
    echo "Membangun ulang service, timer, dan backup-runner berdasarkan config..."
    cat <<'EOR' > "$RUNNER"
#!/bin/bash
CONFIG_FILE="/opt/auto-backup/config.conf"
source "$CONFIG_FILE"

export TZ="${TZ:-UTC}"

BACKUP_DIR="$INSTALL_DIR/backups"
mkdir -p "$BACKUP_DIR"

DATE=$(date +%F-%H%M)
FILE="$BACKUP_DIR/backup-$DATE.tar.gz"
TMP_DIR="$INSTALL_DIR/tmp-$DATE"

mkdir -p "$TMP_DIR"

IFS=',' read -r -a FOLDERS <<< "$FOLDERS_RAW"
for f in "${FOLDERS[@]}"; do
    if [ -d "$f" ]; then
        cp -a "$f" "$TMP_DIR/" || true
    fi
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

if [[ "$USE_MONGO" == "y" && ! -z "$MONGO_MULTI_CONF" ]]; then
    mkdir -p "$TMP_DIR/mongo"
    IFS=';' read -r -a MONGO_ITEMS <<< "$MONGO_MULTI_CONF"
    for ITEM in "${MONGO_ITEMS[@]}"; do
        CREDS=$(echo "$ITEM" | cut -d'@' -f1)
        HOSTPART=$(echo "$ITEM" | cut -d'@' -f2)
        MONGO_USER=$(echo "$CREDS" | cut -d':' -f1)
        MONGO_PASS=$(echo "$CREDS" | cut -d':' -f2)
        MONGO_HOST=$(echo "$HOSTPART" | cut -d':' -f1)
        MONGO_PORT=$(echo "$HOSTPART" | cut -d':' -f2)
        MONGO_AUTHDB=$(echo "$HOSTPART" | cut -d':' -f3)
        MONGO_DB_LIST=$(echo "$HOSTPART" | cut -d':' -f4)

        SAFE_NAME=$(echo "${MONGO_USER}_${MONGO_HOST}_${MONGO_PORT}" | sed 's/[^a-zA-Z0-9._-]/_/g')
        DEST_DIR="$TMP_DIR/mongo/$SAFE_NAME"
        mkdir -p "$DEST_DIR"

        if ! command -v mongodump >/dev/null 2>&1; then
            echo "[WARN] mongodump not found; skip mongo dump for $MONGO_HOST:$MONGO_PORT"
            continue
        fi

        BASE="--host=${MONGO_HOST} --port=${MONGO_PORT} --out=${DEST_DIR}"
        if [[ -n "$MONGO_USER" ]]; then
            BASE="$BASE --username=${MONGO_USER} --password='${MONGO_PASS}' --authenticationDatabase=${MONGO_AUTHDB}"
        fi

        if [[ "$MONGO_DB_LIST" == "all" ]]; then
            eval mongodump $BASE || true
        else
            IFS=',' read -r -a MDBARR <<< "$MONGO_DB_LIST"
            for MDB in "${MDBARR[@]}"; do
                eval mongodump $BASE --db="${MDB}" || true
            done
        fi

        if [[ -d "$DEST_DIR" ]]; then
            tar -czf "${DEST_DIR}.tar.gz" -C "$DEST_DIR" . || true
            rm -rf "$DEST_DIR"
        fi
    done
fi

if [[ "$USE_PG" == "y" ]]; then
    mkdir -p "$TMP_DIR/postgres"
    su - postgres -c "pg_dumpall > $TMP_DIR/postgres/all.sql" || true
fi

tar -czf "$FILE" -C "$TMP_DIR" . || true
echo "[BACKUP_DONE] $(date +%s)" >> /var/log/auto-backup.log
curl -s -F document=@"$FILE" -F caption="Backup selesai: $(basename $FILE)" "https://api.telegram.org/bot$BOT_TOKEN/sendDocument?chat_id=$CHAT_ID" || true
rm -rf "$TMP_DIR"
find "$BACKUP_DIR" -type f -mtime +$RETENTION_DAYS -delete || true
EOR
    chmod +x "$RUNNER"
    echo "[OK] Backup runner dibuat/diupdate: $RUNNER"

    cat <<EOT > "$SERVICE_FILE"
[Unit]
Description=Auto Backup VPS to Telegram
After=network.target mysql.service mariadb.service postgresql.service mongodb.service

[Service]
Type=oneshot
Environment="TZ=$TZ"
ExecStart=/usr/bin/env TZ=$TZ $RUNNER
User=root

[Install]
WantedBy=multi-user.target
EOT

    CURRENT_ONCAL="*-*-* 03:00:00"
    if [[ -f "$TIMER_FILE" ]]; then
        oc=$(grep -E '^OnCalendar=' "$TIMER_FILE" 2>/dev/null | head -n1 | cut -d'=' -f2-)
        if [[ ! -z "$oc" ]]; then CURRENT_ONCAL="$oc"; fi
    fi

    cat <<EOT > "$TIMER_FILE"
[Unit]
Description=Run Auto Backup VPS

[Timer]
OnCalendar=$CURRENT_ONCAL
Persistent=true

[Install]
WantedBy=timers.target
EOT

    systemctl daemon-reload || true
    systemctl enable --now auto-backup.timer || true
    systemctl enable auto-backup.service || true
    echo "[OK] Service & timer dibuat / direpair."
    echo "[$(date '+%F %T')] Rebuilt installer files." >> "$LOGFILE"
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
    echo "Contoh weekly/monthly: 'Mon *-*-* 03:00:00' dsb."
    read -p "Masukkan string OnCalendar yang diinginkan: " OC
    if [[ -z "$OC" ]]; then echo "Tidak ada input."; return; fi
    sed -i "s|OnCalendar=.*|OnCalendar=$OC|g" "$TIMER_FILE"
    systemctl daemon-reload
    systemctl restart auto-backup.timer
    echo "[OK] OnCalendar disimpan ke $TIMER_FILE"
}

show_config_file() {
    echo "================ CONFIG FILE ================"
    cat "$CONFIG"
    echo "============================================"
}

test_backup() {
    echo "[OK] Menjalankan backup-runner (test)..."
    bash "$RUNNER"
    echo "Selesai. Periksa Telegram / $INSTALL_DIR/backups"
}

toggle_mysql() {
    echo "Status sekarang USE_MYSQL = $USE_MYSQL"
    read -p "Aktifkan MySQL? (y/n): " jawab

    case "$jawab" in
        y|Y)
            USE_MYSQL="y"
            echo "[OK] MySQL DI-AKTIFKAN."
            ;;
        n|N)
            USE_MYSQL="n"
            echo "[OK] MySQL DI-MATIKAN."
            ;;
        *)
            echo "Input tidak valid. Gunakan y atau n."
            pause
            return
            ;;
    esac

    save_config
    pause
}

toggle_mongo() {
    echo "Status sekarang USE_MONGO = $USE_MONGO"
    read -p "Aktifkan MongoDB? (y/n): " jawab

    case "$jawab" in
        y|Y)
            USE_MONGO="y"
            echo "[OK] MongoDB DI-AKTIFKAN."
            ;;
        n|N)
            USE_MONGO="n"
            echo "[OK] MongoDB DI-MATIKAN."
            ;;
        *)
            echo "Input tidak valid. Gunakan y atau n."
            pause
            return
            ;;
    esac

    save_config
    pause
}

toggle_pg() {
    echo "Status sekarang USE_PG = $USE_PG"
    read -p "Aktifkan PostgreSQL? (y/n): " jawab

    case "$jawab" in
        y|Y)
            USE_PG="y"
            echo "[OK] PostgreSQL DI-AKTIFKAN."
            ;;
        n|N)
            USE_PG="n"
            echo "[OK] PostgreSQL DI-MATIKAN."
            ;;
        *)
            echo "Input tidak valid. Gunakan y atau n."
            pause
            return
            ;;
    esac

    save_config
    pause
}

# Fungsi untuk ambil status service
get_status_service() {
    # Contoh: cek service backup aktif atau tidak
    if systemctl is-active --quiet auto-backup.service; then
        echo "ACTIVE"
    else
        echo "INACTIVE"
    fi
}

# Fungsi untuk ambil jadwal berikutnya
get_next_schedule() {
    # Contoh: ambil jadwal systemd timer (ubah sesuai timer kamu)
    NEXT=$(systemctl list-timers --no-legend auto-backup.timer | awk 'NR==1 {print $1, $2}')
    if [[ -z "$NEXT" ]]; then
        echo "Belum ada jadwal"
    else
        echo "$NEXT"
    fi
}

# Fungsi untuk ambil backup terakhir
get_last_backup() {
    LAST=$(ls -t /opt/auto-backup/backups/*.tar.gz 2>/dev/null | head -n1)
    if [[ -z "$LAST" ]]; then
        echo "Tidak ada"
    else
        echo "$(basename "$LAST")"
    fi
}

# Fungsi untuk hitung total backup
get_total_backup() {
    COUNT=$(ls /opt/auto-backup/backups/*.tar.gz 2>/dev/null | wc -l)
    echo "${COUNT:-0}"
}

# ===================== WARNA =====================
BLUE="\e[96m"
GREEN="\e[92m"
YELLOW="\e[93m"
RED="\e[91m"
CYAN="\e[36m"
RESET="\e[0m"

# ===================== LOOP REALTIME =====================
while true; do
    clear
    STATUS_SERVICE=$(get_status_service)
    NEXT_RUN=$(get_next_schedule)
    LAST_BACKUP=$(get_last_backup)
    TOTAL_BACKUP=$(get_total_backup)


# ================== DASHBOARD ==================

echo -e "${CYAN}========== BACKUP DASHBOARD BY HENDRI ==========${RESET}"
echo ""
echo -e " Status Service   : ${GREEN}${STATUS_SERVICE}${RESET}"
echo -e " Next Schedule    : ${YELLOW}${NEXT_RUN}${RESET}"
echo -e " Last Backup File : ${RED}${LAST_BACKUP}${RESET}"
echo -e " Total Backup     : ${BLUE}${TOTAL_BACKUP}${RESET}"
echo ""
echo "---------------------- MENU AKSI ---------------------------"
echo -e "${BLUE}[1]  Lihat konfigurasi${RESET}"
echo -e "${YELLOW}[2]  Edit BOT TOKEN${RESET}"
echo -e "${YELLOW}[3]  Edit CHAT ID${RESET}"
echo -e "${YELLOW}[4]  Tambah folder backup${RESET}"
echo -e "${YELLOW}[5]  Hapus folder backup${RESET}"
echo -e "${YELLOW}[6]  Tambah konfigurasi MySQL${RESET}"
echo -e "${YELLOW}[7]  Edit konfigurasi MySQL${RESET}"
echo -e "${YELLOW}[8]  Hapus konfigurasi MySQL${RESET}"
echo -e "${YELLOW}[9]  Tambah konfigurasi MongoDB${RESET}"
echo -e "${YELLOW}[10] Edit konfigurasi MongoDB${RESET}"
echo -e "${YELLOW}[11] Hapus konfigurasi MongoDB${RESET}"
echo -e "${YELLOW}[12] Edit PostgreSQL settings & test dump${RESET}"
echo -e "${YELLOW}[13] Ubah timezone${RESET}"
echo -e "${YELLOW}[14] Ubah retention days${RESET}"
echo -e "${YELLOW}[15] Ubah jadwal backup (OnCalendar helper)${RESET}"

# ---------------- Backup / Restore ----------------
echo -e "${GREEN}[16] Test backup sekarang${RESET}"
echo -e "${GREEN}[17] Restore dari backup${RESET}"
echo -e "${GREEN}[18] Rebuild / Repair installer files (service/timer/runner)${RESET}"
echo -e "${GREEN}[19] Encrypt latest backup (zip with password)${RESET}"

# ---------------- Service / Config ----------------
echo -e "${RED}[20] Restart service & timer${RESET}"
echo -e "${BLUE}[21] Simpan config${RESET}"
echo -e "${BLUE}[22] Status (service / last backup / next run)${RESET}"
echo -e "${BLUE}[23] Status Realtime (live monitor)${RESET}"
echo -e "${BLUE}[24] Gunakan MySQL (use_mysql)${RESET}"
echo -e "${BLUE}[25] Gunakan MongoDB (use_mongo)${RESET}"
echo -e "${BLUE}[26] Gunakan PostgreSQL (use_pg)${RESET}"
echo -e "${RED}[0]  Keluar (tanpa simpan)${RESET}"

echo ""
echo -e "${BLUE}============================================================${RESET}"

    read -p "Pilih menu: " opt

    case "$opt" in
        1) show_config_file; pause ;;
        2) read -p "Masukkan BOT TOKEN baru: " BOT_TOKEN; echo "[OK] BOT_TOKEN updated." ; pause ;;
        3) read -p "Masukkan CHAT ID baru: " CHAT_ID; echo "[OK] CHAT_ID updated." ; pause ;;
        4) add_folder; pause ;;
        5) delete_folder; pause ;;
        6) add_mysql; pause ;;
        7) edit_mysql; pause ;;
        8) delete_mysql; pause ;;
        9) add_mongo; pause ;;
        10) edit_mongo; pause ;;
        11) delete_mongo; pause ;;
        12) edit_pg; pause ;;
        13) read -p "Masukkan timezone (ex: Asia/Jakarta): " NEWTZ; TZ="$NEWTZ"; timedatectl set-timezone "$TZ"; echo "[OK] TZ set to $TZ"; pause ;;
        14) read -p "Masukkan retention days: " RETENTION_DAYS; echo "[OK] Retention set to $RETENTION_DAYS"; pause ;;
        15) build_oncalendar; pause ;;
        16) test_backup; pause ;;
        17) restore_backup; pause ;;
        18) if confirm "Anda yakin ingin (re)build installer files?"; then rebuild_installer_files; fi; pause ;;
        19) encrypt_last_backup; pause ;;
        20) reload_systemd; pause ;;
        21) save_config; pause ;;
        22) show_status ;;
        23) show_status_live ;;
        24) toggle_mysql ;;
        25) toggle_mongo ;;
        26) toggle_pg ;;
        0) echo "Keluar tanpa menyimpan." ; break ;;
        *) echo "Pilihan tidak valid." ; sleep 1 ;;
    esac
done

exit 0
MENU

chmod +x "$MENU_FILE"
ln -sf "$MENU_FILE" /usr/bin/menu-bot-backup
chmod +x /usr/bin/menu-bot-backup

echo "[OK] Menu PRO installed: menu-bot-backup (run 'menu-bot-backup' to open)"

# ======================================================
# Finalize installer
# ======================================================
echo ""
echo "$WATERMARK_END"
echo ""
echo "[INFO] Menjalankan backup pertama (test) sekarang..."
# Run first backup (best-effort, don't fail installer if backup runner errors)
bash "$RUNNER" || echo "[WARN] Backup pertama gagal. Periksa log atau jalankan 'menu-bot-backup' untuk debug."

echo ""
echo "Installer akan menghapus file installer ini untuk keamanan."
rm -- "$0" || true

echo ""
echo "Selesai. Ketik: menu-bot-backup"
