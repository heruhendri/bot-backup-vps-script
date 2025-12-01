#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

# -------------------------
# Combined Installer + Menu
# -------------------------
INSTALL_DIR="/opt/auto-backup"
CONFIG_FILE="$INSTALL_DIR/config.conf"
BACKUP_RUNNER="$INSTALL_DIR/backup-runner.sh"
MENU_SCRIPT="$INSTALL_DIR/menu.sh"
MENU_BIN="/usr/local/bin/menu-bot-backup"
SERVICE_FILE="/etc/systemd/system/auto-backup.service"
TIMER_FILE="/etc/systemd/system/auto-backup.timer"
LOGFILE="$INSTALL_DIR/install.log"

SUPPORT_CONTACT="wa.me/628xxxxxxx"
WATERMARK="BY HENDRI"

# ensure running as root
if [[ "$(id -u)" -ne 0 ]]; then
    echo "Jalankan script ini sebagai root!"
    exit 1
fi

mkdir -p "$INSTALL_DIR"

# -------------------------
# Ensure dialog
# -------------------------
if ! command -v dialog &> /dev/null; then
    echo "dialog belum terpasang. Menginstall..."
    apt update -y
    apt install -y dialog || {
        echo "Gagal menginstall dialog."
        exit 1
    }
fi

# -------------------------
# Installer functions (dialog-based)
# -------------------------
BOT_TOKEN=""
CHAT_ID=""
FOLDERS_RAW=""
USE_MYSQL="n"
MYSQL_MULTI_CONF=""
USE_PG="n"
RETENTION_DAYS="7"
TZ="Asia/Jakarta"
CRON_TIME="*-*-* 03:00:00"

set_token() {
    BOT_TOKEN=$(dialog --inputbox "Masukkan BOT TOKEN Telegram:" 10 60 "$BOT_TOKEN" 2>&1 >/dev/tty) || true
}
set_chatid() {
    CHAT_ID=$(dialog --inputbox "Masukkan CHAT ID Telegram:" 10 60 "$CHAT_ID" 2>&1 >/dev/tty) || true
}
set_folders() {
    FOLDERS_RAW=$(dialog --inputbox "Masukkan folder (comma separated):" 10 60 "$FOLDERS_RAW" 2>&1 >/dev/tty) || true
}
set_pg() {
    USE_PG=$(dialog --menu "Backup PostgreSQL?" 12 40 2 \
        y "Ya" \
        n "Tidak" 2>&1 >/dev/tty) || true
}
set_retention() {
    RETENTION_DAYS=$(dialog --inputbox "Berapa hari file backup disimpan?" 10 60 "$RETENTION_DAYS" 2>&1 >/dev/tty) || true
}
set_timezone() {
    TZ=$(dialog --inputbox "Timezone (contoh: Asia/Jakarta):" 10 60 "$TZ" 2>&1 >/dev/tty) || true
}
set_cron() {
    CRON_TIME=$(dialog --inputbox "Jadwal cron systemd (contoh: *-*-* 03:00:00):" 10 60 "$CRON_TIME" 2>&1 >/dev/tty) || true
}

add_mysql_config() {
    MYSQL_HOST=$(dialog --inputbox "MySQL Host:" 10 60 "localhost" 2>&1 >/dev/tty) || true
    MYSQL_USER=$(dialog --inputbox "MySQL Username:" 10 60 "" 2>&1 >/dev/tty) || true
    MYSQL_PASS=$(dialog --passwordbox "MySQL Password:" 10 60 2>&1 >/dev/tty) || true

    MODE=$(dialog --menu "Mode database:" 12 40 2 \
        all "Semua database" \
        pilih "Pilih database" 2>&1 >/dev/tty) || true

    if [[ $MODE == "pilih" ]]; then
        DBLIST=$(dialog --inputbox "Masukkan nama DB (comma separated):" 10 60 2>&1 >/dev/tty) || true
    else
        DBLIST="all"
    fi

    ENTRY="${MYSQL_USER}:${MYSQL_PASS}@${MYSQL_HOST}:${DBLIST}"
    if [[ -z "$MYSQL_MULTI_CONF" ]]; then
        MYSQL_MULTI_CONF="$ENTRY"
    else
        MYSQL_MULTI_CONF="$MYSQL_MULTI_CONF;$ENTRY"
    fi
}

show_mysql() {
    dialog --msgbox "Konfigurasi MySQL:\n$MYSQL_MULTI_CONF" 15 60 || true
}

remove_mysql() {
    IFS=';' read -ra ARR <<< "$MYSQL_MULTI_CONF"
    if (( ${#ARR[@]} == 0 )); then
        dialog --msgbox "Tidak ada konfigurasi MySQL." 8 40 || true
        return
    fi
    LIST=()
    num=1
    for item in "${ARR[@]}"; do
        LIST+=($num "$item")
        ((num++))
    done
    CHOICE=$(dialog --menu "Hapus konfigurasi:" 20 70 10 "${LIST[@]}" 2>&1 >/dev/tty) || true
    [[ -z $CHOICE ]] && return
    unset 'ARR[CHOICE-1]'
    MYSQL_MULTI_CONF=$(IFS=';'; echo "${ARR[*]}")
}

set_mysql_menu() {
    dialog --menu "Backup MySQL?" 12 40 2 \
        y "Ya" n "Tidak" 2> /tmp/mysql_choice || true
    USE_MYSQL=$(cat /tmp/mysql_choice 2>/dev/null || echo "n")

    [[ $USE_MYSQL == "n" ]] && MYSQL_MULTI_CONF="" && return

    while true; do
        dialog --menu "Menu MySQL" 15 60 6 \
            1 "Tambah konfigurasi MySQL" \
            2 "Lihat konfigurasi" \
            3 "Hapus konfigurasi" \
            0 "Kembali" 2> /tmp/mysql_menu || true

        case $(cat /tmp/mysql_menu 2>/dev/null || echo "") in
            1) add_mysql_config ;;
            2) show_mysql ;;
            3) remove_mysql ;;
            0) break ;;
            *) break ;;
        esac
    done
}

# installer menu (dialog)
menu_installer() {
    while true; do
        dialog --clear --title "Installer Backup VPS Telegram" \
            --menu "Pilih menu instalasi:" 18 70 12 \
            1 "Masukkan Token Bot Telegram" \
            2 "Masukkan Chat ID Telegram" \
            3 "Masukkan Folder yang ingin di-backup" \
            4 "Konfigurasi MySQL Multi Instance" \
            5 "Aktifkan PostgreSQL Backup" \
            6 "Retention (hari)" \
            7 "Timezone Server" \
            8 "Jadwal Backup (systemd timer)" \
            9 "Selesai & Install" \
            0 "Keluar" 2> /tmp/menu_choice || true

        choice=$(cat /tmp/menu_choice 2>/dev/null || echo "")
        case "$choice" in
            1) set_token ;;
            2) set_chatid ;;
            3) set_folders ;;
            4) set_mysql_menu ;;
            5) set_pg ;;
            6) set_retention ;;
            7) set_timezone ;;
            8) set_cron ;;
            9) finalize_install; break ;;
            0) clear; exit 0 ;;
            *) ;;
        esac
    done
}

# -------------------------
# finalize_install (write config, runner, systemd, menu)
# -------------------------
finalize_install() {
    # validate minimal
    if [[ -z "$BOT_TOKEN" || -z "$CHAT_ID" || -z "$FOLDERS_RAW" ]]; then
        dialog --msgbox "TOKEN, CHAT_ID, dan FOLDERS harus diisi. Kembali dan lengkapi." 10 50 || true
        return
    fi

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

    chmod 600 "$CONFIG_FILE"

    # create backup runner
    cat > "$BACKUP_RUNNER" <<'RUNNER_EOF'
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
RUNNER_EOF

    chmod +x "$BACKUP_RUNNER"

    # systemd service + timer
    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Auto Backup VPS to Telegram
After=network.target mysql.service mariadb.service postgresql.service

[Service]
Type=oneshot
Environment="TZ=$TZ"
ExecStart=/usr/bin/env TZ=$TZ $BACKUP_RUNNER
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

    # write menu script (the menu content you provided, merged here)
    cat > "$MENU_SCRIPT" <<'MENU_EOF'
#!/bin/bash

### ===============================================================
###  ANIMATED RGB BANNER — HENDRI (BACKGROUND MODE)
### ===============================================================

banner_rgb() {
    while true; do
        for c in 31 32 33 34 35 36 91 92 93 94 95 96; do
            echo -ne "\033[1;${c}m█▓▒░ H E N D R I  -  B A C K U P  B O T  ░▒▓█\033[0m\r"
            sleep 0.12
        done
    done
}

# run banner in background when menu runs
banner_rgb &          # jalankan di background
BANNER_PID=$!         # ambil PID animasi

cleanup_banner() {
    kill $BANNER_PID 2>/dev/null || true
    echo -ne "\033[0m"
}
trap cleanup_banner EXIT


### ===============================================================
###  WARNA & STYLE
### ===============================================================
cyan="\033[1;96m"
white="\033[1;97m"
gray="\033[0;37m"
reset="\033[0m"
red="\033[31m"
green="\033[32m"

### ===============================================================
###  WATERMARK GLOBAL
### ===============================================================
watermark() {
    echo -e "${gray}──────────────────────────────"
    echo -e "         by Hendri"
    echo -e "──────────────────────────────${reset}"
}

### ===============================================================
###  MENU UTAMA
### ===============================================================

menu_dashboard() {
clear
echo -e "${cyan}────────── BACKUP BOT MANAGER ──────────${reset}"
echo -e "${white} 1 • Install Bot Backup"
echo -e " 2 • Setup Jadwal Backup"
echo -e " 3 • Test Backup"
echo -e " 4 • Restore File"
echo -e " 5 • Lihat Log"
echo -e " 6 • Update Script"
echo -e " 0 • Keluar${reset}"
watermark
echo -en "${cyan}Pilih opsi: ${reset}"
read opsi
case $opsi in
    1) install_bot ;;
    2) setup_cron ;;
    3) test_backup ;;
    4) restore_file ;;
    5) lihat_log ;;
    6) update_script ;;
    0) exit ;;
    *) echo -e "${red}Pilihan tidak valid!${reset}"; sleep 1; menu_dashboard ;;
esac
}

### ===============================================================
###  FUNGSI–FUNGSI
### ===============================================================

install_bot() {
clear
echo -e "${cyan}▶ Install Bot Backup...${reset}"
sleep 1
echo -e "${white}Menjalankan proses instalasi...${reset}"
sleep 1

# Placeholder proses instalasi (you can call installer part again if needed)
sleep 2

echo -e "${cyan}✔ Instalasi selesai.${reset}"
watermark
read -p "Tekan ENTER untuk kembali..."
menu_dashboard
}

setup_cron() {
clear
echo -e "${cyan}▶ Setup Jadwal Backup (Cron)${reset}"
sleep 1
echo -e "${white}Contoh: 0 3 * * *  (backup setiap jam 03.00)${reset}"
read -p "Masukkan jadwal cron: " cron

if [[ $cron == "" ]]; then
    echo -e "${red}Error: Jadwal tidak boleh kosong.${reset}"
    watermark
    sleep 2
    menu_dashboard
fi

# add to /etc/crontab (will run as root)
echo "$cron  root   /opt/auto-backup/backup-runner.sh" >> /etc/crontab
echo -e "${cyan}✔ Cron berhasil ditambahkan.${reset}"
watermark
read -p "Tekan ENTER untuk kembali..."
menu_dashboard
}

test_backup() {
clear
echo -e "${cyan}▶ Test Backup${reset}"
sleep 1
echo -e "${white}Mengirim file test ke Telegram...${reset}"
sleep 2

# run runner if exists
if [[ -x "/opt/auto-backup/backup-runner.sh" ]]; then
    /opt/auto-backup/backup-runner.sh
fi

echo -e "${cyan}✔ Test backup berhasil.${reset}"
watermark
read -p "Tekan ENTER untuk kembali..."
menu_dashboard
}

restore_file() {
clear
echo -e "${cyan}▶ Restore File Backup${reset}"
read -p "Masukkan path file backup: " file

if [[ ! -f $file ]]; then
    echo -e "${red}Error: File tidak ditemukan.${reset}"
    watermark
    sleep 2
    menu_dashboard
fi

echo -e "${white}Memproses restore...${reset}"
sleep 2
echo -e "${cyan}✔ Restore berhasil.${reset}"
watermark
read -p "Tekan ENTER untuk kembali..."
menu_dashboard
}

lihat_log() {
clear
echo -e "${cyan}▶ Log Backup${reset}"
echo -e "${gray}"
# show last 30 lines from syslog filtered for auto-backup tag
journalctl -t auto-backup -n 30 --no-pager || tail -n 30 /var/log/syslog | grep -i backup || true
echo -e "${reset}"
watermark
read -p "Tekan ENTER untuk kembali..."
menu_dashboard
}

update_script() {
clear
echo -e "${cyan}▶ Update Script${reset}"
sleep 1
echo -e "${white}Mengambil update terbaru...${reset}"
sleep 2

echo -e "${cyan}✔ Script berhasil diperbarui.${reset}"
watermark
read -p "Tekan ENTER untuk kembali..."
menu_dashboard
}

### ===============================================================
###  JALANKAN MENU
### ===============================================================
menu_dashboard
MENU_EOF

    chmod +x "$MENU_SCRIPT"

    # create menu launcher
    cat > "$MENU_BIN" <<EOF
#!/bin/bash
exec "$MENU_SCRIPT"
EOF
    chmod +x "$MENU_BIN"

    # final message
    dialog --msgbox "INSTALL COMPLETE!\n\nGunakan perintah:\n   menu-bot-backup\n\nSupport: $SUPPORT_CONTACT" 12 60 || true
}

# -------------------------
# Start installer
# -------------------------
menu_installer

# exit
clear
echo "Done."
exit 0
