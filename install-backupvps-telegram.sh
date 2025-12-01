#!/bin/bash
clear

# ==================================================
#  AUTO INSTALLER BACKUP VPS — TELEGRAM (DASHBOARD)
# ==================================================

# --------------------------------------------
#  CEK & INSTALL dialog
# --------------------------------------------
if ! command -v dialog &> /dev/null; then
    echo "dialog belum terpasang. Menginstall..."
    apt update -y
    apt install dialog -y || {
        echo "Gagal install dialog."
        exit 1
    }
fi

# --------------------------------------------
#  FUNGSI INSTALL BOT
# --------------------------------------------
install_bot(){
    clear
    dialog --msgbox "Mulai instalasi Bot Backup VPS..." 7 40

    apt update -y
    apt install -y curl jq wget unzip cron

    # Folder bot
    mkdir -p /opt/bot-backup
    cd /opt/bot-backup || exit

    # Buat file config default
    cat > config.json << END
{
    "bot_token": "ISI_TOKEN_BOT",
    "chat_id": "ISI_CHAT_ID",
    "backup_path": "/root",
    "backup_dir": "/opt/bot-backup/data",
    "retention_days": 3
}
END

    mkdir -p data logs

    # File bot utama
    cat > bot-backup.sh << 'EOF'
#!/bin/bash

CONFIG="/opt/bot-backup/config.json"

TOKEN=$(jq -r .bot_token $CONFIG)
CHAT_ID=$(jq -r .chat_id $CONFIG)
BACKUP_PATH=$(jq -r .backup_path $CONFIG)
RETENTION=$(jq -r .retention_days $CONFIG)
BACKUP_DIR=$(jq -r .backup_dir $CONFIG)

DATE=$(date "+%Y-%m-%d_%H-%M")
FILE="backup-$DATE.tar.gz"

mkdir -p "$BACKUP_DIR"

tar -czf "$BACKUP_DIR/$FILE" $BACKUP_PATH 2>/opt/bot-backup/logs/error.log

curl -F document=@"$BACKUP_DIR/$FILE" \
     -F chat_id="$CHAT_ID" \
     -F caption="Backup VPS Selesai: $FILE" \
     https://api.telegram.org/bot$TOKEN/sendDocument >/dev/null 2>&1

# Auto bersihkan backup lama
find "$BACKUP_DIR" -mtime +$RETENTION -delete
EOF

    chmod +x bot-backup.sh

    # --------------------------------------------
    #  BUAT DASHBOARD MENU
    # --------------------------------------------
    cat > /usr/bin/menu-bot-backup << 'EOF'
#!/bin/bash
CONFIG="/opt/bot-backup/config.json"

TITLE="=== DASHBOARD BACKUP VPS ==="
MENU=$(dialog --clear --stdout --title "$TITLE" --menu "Pilih Opsi:" 20 60 10 \
1 "🛠  Set Token Bot" \
2 "🆔  Set Chat ID" \
3 "📁  Set Folder Backup" \
4 "📂  Lihat File Backup" \
5 "📨  Kirim Backup Sekarang" \
6 "⏱  Jadwalkan Harian" \
7 "🧹  Set Retensi Backup" \
8 "📄  Lihat Konfigurasi" \
9 "❌  Keluar")

case $MENU in
1)
    TOKEN=$(dialog --stdout --inputbox "Masukkan token bot:" 8 50)
    jq --arg t "$TOKEN" '.bot_token=$t' $CONFIG > /opt/bot-backup/tmp.json && mv /opt/bot-backup/tmp.json $CONFIG
    ;;
2)
    CID=$(dialog --stdout --inputbox "Masukkan chat ID:" 8 50)
    jq --arg c "$CID" '.chat_id=$c' $CONFIG > /opt/bot-backup/tmp.json && mv /opt/bot-backup/tmp.json $CONFIG
    ;;
3)
    FOLDER=$(dialog --stdout --inputbox "Folder yang ingin di-backup:" 8 50)
    jq --arg f "$FOLDER" '.backup_path=$f' $CONFIG > /opt/bot-backup/tmp.json && mv /opt/bot-backup/tmp.json $CONFIG
    ;;
4)
    dialog --textbox /opt/bot-backup/logs/error.log 20 70
    ;;
5)
    bash /opt/bot-backup/bot-backup.sh
    dialog --msgbox "Backup terkirim!" 6 30
    ;;
6)
    # Jadwal backup harian jam 00.00
    echo "0 0 * * * root bash /opt/bot-backup/bot-backup.sh" > /etc/cron.d/backupbot
    systemctl restart cron
    dialog --msgbox "Jadwal harian diaktifkan!" 6 40
    ;;
7)
    RET=$(dialog --stdout --inputbox "Retensi (hari):" 8 40)
    jq --arg r "$RET" '.retention_days=$r|tonumber' $CONFIG > /opt/bot-backup/tmp.json && mv /opt/bot-backup/tmp.json $CONFIG
    ;;
8)
    dialog --textbox $CONFIG 20 70
    ;;
9)
    clear
    exit
    ;;
esac

bash /usr/bin/menu-bot-backup
EOF

    chmod +x /usr/bin/menu-bot-backup

    dialog --msgbox "INSTALASI SELESAI!\n\nKetik: menu-bot-backup" 10 50
    clear
}

# --------------------------------------------
#  MENU INSTALLER
# --------------------------------------------
while true; do
    CHOICE=$(dialog --clear --stdout --title "INSTALLER BOT BACKUP VPS" --menu "Pilih Menu:" 20 60 10 \
    1 "Install Bot Backup VPS" \
    2 "Update Script" \
    3 "Uninstall Bot" \
    4 "Keluar")

    case "$CHOICE" in
        1) install_bot ;;
        2) dialog --msgbox "Belum tersedia." 6 30 ;;
        3)
            rm -rf /opt/bot-backup
            rm -f /usr/bin/menu-bot-backup
            dialog --msgbox "UNINSTALL BERHASIL" 6 30
            ;;
        4) clear; exit ;;
    esac
done