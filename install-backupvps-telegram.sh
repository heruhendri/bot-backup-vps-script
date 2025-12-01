#!/bin/bash
clear

# =====================================================
#   AUTO INSTALLER + DASHBOARD MENU BACKUP VPS BOT
#   Dashboard Style: CLEAN UI (Dashboard 3)
# =====================================================

INSTALL_PATH="/opt/backupvps"
MENU_PATH="/usr/bin/menu-bot-backup"
CONFIG_FILE="$INSTALL_PATH/config.conf"

# -----------------------------------------------------
# WARNA
# -----------------------------------------------------
red='\e[31m'
green='\e[32m'
yellow='\e[33m'
cyan='\e[36m'
nc='\e[0m'

# -----------------------------------------------------
# CEK AKSES ROOT
# -----------------------------------------------------
if [[ $EUID -ne 0 ]]; then
   echo -e "${red}Harus dijalankan sebagai root!${nc}"
   exit 1
fi


# -----------------------------------------------------
# INSTALL DEPENDENSI
# -----------------------------------------------------
echo -e "${green}Menginstall dependensi...${nc}"
apt update -y
apt install -y curl wget zip unzip jq bc cron


# -----------------------------------------------------
# MEMBUAT DIRECTORI SISTEM
# -----------------------------------------------------
mkdir -p $INSTALL_PATH
mkdir -p $INSTALL_PATH/mysql
mkdir -p $INSTALL_PATH/postgresql
mkdir -p $INSTALL_PATH/backups


# -----------------------------------------------------
# CONFIG DEFAULT
# -----------------------------------------------------
if [[ ! -f $CONFIG_FILE ]]; then
cat > $CONFIG_FILE <<EOF
TELEGRAM_TOKEN=""
TELEGRAM_CHATID=""
BACKUP_FOLDER="/root"
RETENTION=3
EOF
fi


# -----------------------------------------------------
# FUNGSI EDIT CONFIG
# -----------------------------------------------------
edit_config() {
    clear
    echo "==========================================="
    echo "       EDIT KONFIGURASI BACKUP BOT"
    echo "==========================================="

    read -rp "Token Bot Telegram       : " token
    read -rp "Chat ID Telegram         : " chatid
    read -rp "Folder Backup (default:/root) : " folder
    read -rp "Retention file (default: 3)   : " retention

cat > $CONFIG_FILE <<EOF
TELEGRAM_TOKEN="$token"
TELEGRAM_CHATID="$chatid"
BACKUP_FOLDER="${folder:-/root}"
RETENTION="${retention:-3}"
EOF

    echo ""
    echo -e "${green}Konfigurasi berhasil disimpan!${nc}"
    read -p "Tekan ENTER untuk kembali..."
}


# -----------------------------------------------------
# FUNGSI BACKUP MANUAL
# -----------------------------------------------------
backup_now() {
    source $CONFIG_FILE
    NOW=$(date +%Y-%m-%d_%H-%M)
    FILE="$INSTALL_PATH/backups/backup-$NOW.zip"

    zip -r "$FILE" "$BACKUP_FOLDER" >/dev/null 2>&1

    curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendDocument" \
         -F chat_id="$TELEGRAM_CHATID" \
         -F document=@"$FILE"

    echo -e "${green}Backup selesai & dikirim ke Telegram.${nc}"
    read -p "Tekan ENTER untuk kembali..."
}


# -----------------------------------------------------
# FUNGSI MELIHAT FILE BACKUP
# -----------------------------------------------------
list_backups() {
    clear
    echo "==========================================="
    echo "            DAFTAR FILE BACKUP"
    echo "==========================================="
    ls -lh $INSTALL_PATH/backups
    echo "==========================================="
    read -p "Tekan ENTER untuk kembali..."
}


# -----------------------------------------------------
# FUNGSI RESTORE BACKUP
# -----------------------------------------------------
restore_backup() {
    clear
    echo "==========================================="
    echo "              RESTORE BACKUP"
    echo "==========================================="

    ls -lh $INSTALL_PATH/backups
    echo ""
    read -rp "Masukkan nama file backup: " FILE

    if [[ ! -f "$INSTALL_PATH/backups/$FILE" ]]; then
        echo -e "${red}File tidak ditemukan!${nc}"
        sleep 2
        return
    fi

    unzip "$INSTALL_PATH/backups/$FILE" -d / >/dev/null 2>&1
    echo -e "${green}Restore selesai.${nc}"
    read -p "Tekan ENTER untuk kembali..."
}


# -----------------------------------------------------
# MENULIS MENU GLOBAL /usr/bin/menu-bot-backup
# -----------------------------------------------------
cat > $MENU_PATH <<'MENUEND'
#!/bin/bash
CONFIG="/opt/backupvps/config.conf"
INSTALL_PATH="/opt/backupvps"

# Warna
green='\e[32m'
nc='\e[0m'

while true; do
clear
echo "==========================================="
echo "   AUTO BACKUP VPS — TELEGRAM BOT MENU"
echo "==========================================="
echo ""
echo " (1) Edit Folder & Config"
echo " (2) Edit MySQL Config"
echo " (3) Edit PostgreSQL Config"
echo " (4) Lihat Jadwal Backup"
echo " (5) Lihat File Backup"
echo " (6) Restore Backup"
echo " (7) Jalankan Backup Manual"
echo " (0) Keluar"
echo ""
echo "==========================================="
read -rp "Pilih menu: " men

case $men in

1)
    bash /opt/backupvps/edit_config.sh
    ;;

2)
    nano /opt/backupvps/mysql/config.json
    ;;

3)
    nano /opt/backupvps/postgresql/config.json
    ;;

4)
    systemctl list-timers --all
    read -p "Tekan ENTER..."
    ;;

5)
    ls -lh /opt/backupvps/backups
    read -p "Tekan ENTER..."
    ;;

6)
    bash /opt/backupvps/restore.sh
    ;;

7)
    bash /opt/backupvps/backup_now.sh
    ;;

0)
    exit ;;

*)
    echo "Pilihan tidak valid!"
    sleep 1
    ;;
esac
done
MENUEND

chmod +x $MENU_PATH


# -----------------------------------------------------
# COPY FUNGSI KE FILE TERPISAH AGAR DIPAKAI MENU
# -----------------------------------------------------
cat > /opt/backupvps/backup_now.sh <<EOF
#!/bin/bash
$(declare -f backup_now)
backup_now
EOF
chmod +x /opt/backupvps/backup_now.sh

cat > /opt/backupvps/edit_config.sh <<EOF
#!/bin/bash
$(declare -f edit_config)
edit_config
EOF
chmod +x /opt/backupvps/edit_config.sh

cat > /opt/backupvps/restore.sh <<EOF
#!/bin/bash
$(declare -f restore_backup)
restore_backup
EOF
chmod +x /opt/backupvps/restore.sh



# -----------------------------------------------------
# SELESAI
# -----------------------------------------------------
clear
echo -e "${green}================================================${nc}"
echo -e "${green} INSTALLASI SELESAI!${nc}"
echo -e "${green} Jalankan menu dengan perintah:${nc}"
echo ""
echo -e "         ${yellow}menu-bot-backup${nc}"
echo ""
echo -e "${green}================================================${nc}"
