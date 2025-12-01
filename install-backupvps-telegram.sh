#!/bin/bash

# Warna
CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

clear

# ======================================================
# WATERMARK & HEADER
# ======================================================
echo -e "${CYAN}====================================================${NC}"
echo -e "${CYAN}        AUTO BACKUP VPS — TELEGRAM BOT INSTALLER    ${NC}"
echo -e "${YELLOW}           By Hendri Contact Support Telegram       ${NC}"
echo -e "${CYAN}====================================================${NC}"
echo ""

# Cek Root
if [ "${EUID}" -ne 0 ]; then
		echo -e "${RED}Error: Script ini harus dijalankan sebagai root.${NC}"
		exit 1
fi

INSTALL_DIR="/opt/auto-backup"
CONFIG_FILE="$INSTALL_DIR/config.conf"
MENU_BIN="/usr/bin/menu-bot-backup"

mkdir -p "$INSTALL_DIR"

# ======================================================
# 1. DETEKSI CONFIG LAMA
# ======================================================
SKIP_INPUT=false

if [[ -f "$CONFIG_FILE" ]]; then
    echo -e "${YELLOW}[!] Konfigurasi lama terdeteksi di $CONFIG_FILE${NC}"
    read -p "Apakah Anda ingin mengganti (replace) konfigurasi lama? (y/n): " REPLACE_CONF
    
    if [[ "$REPLACE_CONF" == "n" || "$REPLACE_CONF" == "N" ]]; then
        echo -e "${GREEN}[OK] Menggunakan konfigurasi yang sudah ada.${NC}"
        source "$CONFIG_FILE"
        SKIP_INPUT=true
    else
        echo -e "${RED}[!] Konfigurasi lama akan ditimpa.${NC}"
    fi
fi

# ======================================================
# 2. INPUT DATA (JIKA TIDAK SKIP)
# ======================================================
if [[ "$SKIP_INPUT" == "false" ]]; then
    echo ""
    read -p "Masukkan TOKEN Bot Telegram: " BOT_TOKEN
    read -p "Masukkan CHAT_ID Telegram: " CHAT_ID
    read -p "Masukkan folder yang mau di-backup (comma separated, contoh: /etc,/var/www): " FOLDERS_RAW

    # --- MYSQL SETUP ---
    echo ""
    read -p "Backup MySQL? (y/n): " USE_MYSQL
    MYSQL_MULTI_CONF=""
    if [[ "$USE_MYSQL" == "y" ]]; then
        read -p "Berapa konfigurasi MySQL yang ingin Anda tambahkan? " MYSQL_COUNT
        
        for ((i=1; i<=MYSQL_COUNT; i++)); do
            echo ""
            echo -e "${BLUE}📌 Konfigurasi MySQL ke-$i${NC}"
            
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

    # --- POSTGRES & SYSTEM SETUP ---
    echo ""
    read -p "Backup PostgreSQL? (y/n): " USE_PG
    read -p "Retention (berapa hari file backup disimpan): " RETENTION_DAYS
    read -p "Timezone (contoh: Asia/Jakarta): " TZ
    read -p "Jadwal cron (format systemd timer, contoh: *-*-* 03:00:00): " CRON_TIME

    # --- SIMPAN CONFIG ---
    echo -e "${GREEN}[OK] Setting timezone sistem...${NC}"
    timedatectl set-timezone "$TZ"

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
CRON_TIME="$CRON_TIME"
EOF
    echo -e "${GREEN}[OK] Config saved: $CONFIG_FILE${NC}"
fi

# ======================================================
# 3. CREATE BACKUP RUNNER (Backend)
# ======================================================
# Kita rebuild file runner untuk memastikan code terbaru terpasang
cat <<'EOF' > "$INSTALL_DIR/backup-runner.sh"
#!/bin/bash
CONFIG_FILE="/opt/auto-backup/config.conf"
source "$CONFIG_FILE"

export TZ="$TZ"

BACKUP_DIR="$INSTALL_DIR/backups"
mkdir -p "$BACKUP_DIR"

DATE=$(date +%F-%H%M)
FILE="$BACKUP_DIR/backup-$DATE.tar.gz"
TMP_DIR="$INSTALL_DIR/tmp-$DATE"

mkdir -p "$TMP_DIR"

# 1. BACKUP FOLDERS
IFS=',' read -r -a FOLDERS <<< "$FOLDERS_RAW"
for f in "${FOLDERS[@]}"; do
    if [ -d "$f" ]; then
        cp -r "$f" "$TMP_DIR/"
    fi
done

# 2. BACKUP MYSQL
if [[ "$USE_MYSQL" == "y" ]]; then
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
            mysqldump $MYSQL_ARGS --all-databases > "$OUTFILE" 2>/dev/null
        else
            IFS=',' read -r -a DBARR <<< "$MYSQL_DB_LIST"
            for DB in "${DBARR[@]}"; do
                OUTFILE="$TMP_DIR/mysql/${MYSQL_USER}@${MYSQL_HOST}_${DB}.sql"
                mysqldump $MYSQL_ARGS "$DB" > "$OUTFILE" 2>/dev/null
            done
        fi
    done
fi

# 3. BACKUP POSTGRES
if [[ "$USE_PG" == "y" ]]; then
    mkdir -p "$TMP_DIR/postgres"
    su - postgres -c "pg_dumpall > $TMP_DIR/postgres/all.sql" 2>/dev/null
fi

# 4. COMPRESS
tar -czf "$FILE" -C "$TMP_DIR" .

# 5. SEND TELEGRAM
CAPTION="✅ <b>Backup VPS Selesai</b>%0A"
CAPTION+="📅 Date: $(date)%0A"
CAPTION+="📂 File: $(basename $FILE)%0A"
CAPTION+="💾 Size: $(du -h $FILE | cut -f1)%0A"
CAPTION+="%23AutoBackup By Hendri"

curl -s -F document=@"$FILE" \
     -F caption="$CAPTION" -F parse_mode="HTML" \
     "https://api.telegram.org/bot$BOT_TOKEN/sendDocument?chat_id=$CHAT_ID"

# 6. CLEANUP
rm -rf "$TMP_DIR"
find "$BACKUP_DIR" -type f -mtime +$RETENTION_DAYS -delete
EOF

chmod +x "$INSTALL_DIR/backup-runner.sh"
echo -e "${GREEN}[OK] Backup runner updated.${NC}"

# ======================================================
# 4. CREATE SYSTEMD SERVICE & TIMER
# ======================================================
# Load config ulang untuk memastikan CRON_TIME benar jika skip input
source "$CONFIG_FILE"
CRON_TIME=${CRON_TIME:-"*-*-* 03:00:00"} 

cat <<EOF > /etc/systemd/system/auto-backup.service
[Unit]
Description=Auto Backup VPS to Telegram
After=network.target mysql.service mariadb.service postgresql.service

[Service]
Type=oneshot
Environment="TZ=$TZ"
ExecStart=/usr/bin/env TZ=$TZ $INSTALL_DIR/backup-runner.sh
User=root

[Install]
WantedBy=multi-user.target
EOF

cat <<EOF > /etc/systemd/system/auto-backup.timer
[Unit]
Description=Run Auto Backup VPS

[Timer]
OnCalendar=$CRON_TIME
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable auto-backup.service
systemctl enable --now auto-backup.timer

# ======================================================
# 5. INSTALL MENU SCRIPT (DASHBOARD UI)
# ======================================================
cat <<'EOF' > "$MENU_BIN"
#!/bin/bash

# Config & Paths
CONFIG="/opt/auto-backup/config.conf"
INSTALL_DIR="/opt/auto-backup"
RUNNER="$INSTALL_DIR/backup-runner.sh"
LOGFILE="$INSTALL_DIR/menu.log"

# Colors
CYAN='\033[0;36m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

if [[ ! -f "$CONFIG" ]]; then
    echo -e "${RED}Config file not found!${NC}"
    exit 1
fi

source "$CONFIG"

# --- Functions ---
save_config() {
    cat <<EOC > "$CONFIG"
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
EOC
}

pause() {
    echo ""
    read -p "Tekan ENTER untuk kembali ke menu..."
}

# --- Features ---

function run_backup_now() {
    echo -e "${GREEN}Memulai proses backup manual...${NC}"
    bash "$RUNNER"
    echo -e "${GREEN}Backup selesai! Cek bot telegram Anda.${NC}"
    pause
}

function list_backups() {
    echo -e "${CYAN}=== DAFTAR FILE BACKUP ===${NC}"
    ls -lh "$INSTALL_DIR/backups" | awk '{print $9, $5}'
    pause
}

function manage_folders() {
    echo -e "${CYAN}Folder saat ini:${NC} $FOLDERS_RAW"
    echo ""
    echo "1) Tambah Folder"
    echo "2) Hapus Semua & Reset"
    read -p "Pilihan: " optf
    case $optf in
        1) 
            read -p "Path folder baru: " newf
            if [ -d "$newf" ]; then
                if [ -z "$FOLDERS_RAW" ]; then FOLDERS_RAW="$newf"; else FOLDERS_RAW="$FOLDERS_RAW,$newf"; fi
                save_config
                echo "Folder ditambahkan."
            else
                echo "Folder tidak ditemukan di sistem."
            fi
            ;;
        2)
            FOLDERS_RAW=""
            save_config
            echo "Daftar folder dikosongkan."
            ;;
    esac
    pause
}

function system_info() {
    echo -e "${CYAN}=== SYSTEM INFO ===${NC}"
    echo "OS       : $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
    echo "Uptime   : $(uptime -p)"
    echo "Disk     : $(df -h / | awk 'NR==2 {print $4 " free / " $2 " total"}')"
    echo "Config   : $CONFIG"
    echo "Location : $INSTALL_DIR"
    pause
}

function db_settings() {
    echo -e "${CYAN}=== PENGATURAN DATABASE ===${NC}"
    echo "MySQL Backup : $USE_MYSQL"
    echo "PG Backup    : $USE_PG"
    echo ""
    echo "1. Toggle MySQL (y/n)"
    echo "2. Toggle PostgreSQL (y/n)"
    echo "3. Reset Konfigurasi MySQL Multi"
    read -p "Pilih: " dbopt
    
    case $dbopt in
        1) read -p "Enable MySQL? (y/n): " USE_MYSQL; save_config ;;
        2) read -p "Enable Postgres? (y/n): " USE_PG; save_config ;;
        3) MYSQL_MULTI_CONF=""; echo "MySQL Config direset. Silahkan jalankan installer ulang untuk menambah."; save_config ;;
    esac
    pause
}

function edit_schedule() {
    echo -e "${CYAN}Jadwal saat ini (Systemd):${NC} $CRON_TIME"
    read -p "Masukkan jadwal baru (format systemd, ex: *-*-* 01:00:00): " NEW_TIME
    if [[ ! -z "$NEW_TIME" ]]; then
        CRON_TIME="$NEW_TIME"
        save_config
        # Update timer file
        sed -i "s|OnCalendar=.*|OnCalendar=$CRON_TIME|g" /etc/systemd/system/auto-backup.timer
        systemctl daemon-reload
        systemctl restart auto-backup.timer
        echo -e "${GREEN}Jadwal berhasil diupdate!${NC}"
    fi
    pause
}

# --- Main Dashboard Loop ---
while true; do
    clear
    # Data Realtime
    IS_ACTIVE=$(systemctl is-active auto-backup.timer)
    if [[ "$IS_ACTIVE" == "active" ]]; then STATUS="${GREEN}ACTIVE${NC}"; else STATUS="${RED}INACTIVE${NC}"; fi
    
    NEXT_RUN=$(systemctl list-timers --no-pager | grep auto-backup.timer | awk '{print $2, $3}')
    LAST_FILE=$(ls -t "$INSTALL_DIR/backups" 2>/dev/null | head -n1)
    TOTAL_FILE=$(ls "$INSTALL_DIR/backups" 2>/dev/null | wc -l)
    
    # Header Watermark
    echo -e "${CYAN}==================== BACKUP DASHBOARD ====================${NC}"
    echo -e "${YELLOW}           By Hendri Contact Support Telegram             ${NC}"
    echo -e "${CYAN}==========================================================${NC}"
    echo ""
    echo -e " Status Service   : $STATUS"
    echo -e " Next Schedule    : ${PURPLE}$NEXT_RUN${NC}"
    echo -e " Last Backup File : ${YELLOW}${LAST_FILE:-Belum ada backup}${NC}"
    echo -e " Total Backup     : $TOTAL_FILE File(s)"
    echo ""
    echo -e "${CYAN}---------------------- MENU AKSI -------------------------${NC}"
    echo -e " [1] Jalankan Backup Sekarang"
    echo -e " [2] Status Backup Lengkap (Logs)"
    echo -e " [3] Daftar File Backup"
    echo -e " [4] Atur Folder Backup"
    echo -e " [5] System Info Backup"
    echo -e " [6] Pengaturan Database"
    echo -e " [7] Ubah Jadwal Otomatis"
    echo -e " [0] Keluar"
    echo ""
    echo -e "${CYAN}==========================================================${NC}"
    read -p " Masukkan Pilihan: " menu_opt

    case $menu_opt in
        1) run_backup_now ;;
        2) systemctl status auto-backup.service; pause ;;
        3) list_backups ;;
        4) manage_folders ;;
        5) system_info ;;
        6) db_settings ;;
        7) edit_schedule ;;
        0) echo "Bye bye!"; exit 0 ;;
        *) echo "Pilihan salah!"; sleep 1 ;;
    esac
done
EOF

chmod +x "$MENU_BIN"

# ======================================================
# 6. FINISHING
# ======================================================
echo ""
echo -e "${GREEN}===========================================${NC}"
echo -e "${GREEN}   INSTALL / UPDATE COMPLETE!              ${NC}"
echo -e "${GREEN}===========================================${NC}"
echo -e "Command Menu : ${YELLOW}menu-bot-backup${NC}"
echo -e "Service      : auto-backup.service"
echo -e "Timer        : auto-backup.timer"
echo -e "Config       : $CONFIG_FILE"
echo ""

if [[ "$SKIP_INPUT" == "false" ]]; then
    echo -e "${CYAN}Testing backup pertama...${NC}"
    bash "$INSTALL_DIR/backup-runner.sh"
    echo -e "${GREEN}Backup pertama dikirim ke Telegram.${NC}"
fi

# Hapus installer diri sendiri (opsional, amannya di comment saja kalau mau disimpan)
# rm -- "$0"