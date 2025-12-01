#!/bin/bash
clear

# ==================================================
#  AUTO INSTALLER BACKUP VPS — TELEGRAM (DIALOG UI)
#  Watermark by: Hendri | Support: t.me/hendrichat
# ==================================================

echo "==============================================================="
echo "  AUTO INSTALLER BACKUP VPS TELEGRAM"
echo "  Created by: Hendri — Contact support jika ada error"
echo "==============================================================="
sleep 2

# --------------------------------------------
#  CEK & INSTALL dialog
# --------------------------------------------
if ! command -v dialog &> /dev/null; then
    echo "[INFO] dialog belum terpasang. Menginstall..."
    apt update -y
    apt install dialog -y || {
        echo "[ERROR] Gagal menginstall dialog."
        exit 1
    }
fi

INSTALL_DIR="/opt/auto-backup"
CONFIG_FILE="$INSTALL_DIR/config.conf"
BACKUP_RUNNER="$INSTALL_DIR/backup-runner.sh"

mkdir -p "$INSTALL_DIR"

# --------------------------------------------
#  GLOBAL INSTALLER MENU
# --------------------------------------------
menu_installer() {
    dialog --clear --title "Installer Backup VPS Telegram" \
        --menu "Pilih menu instalasi:\n(Branding by Hendri Support)" 22 70 12 \
        1 "Masukkan Token Bot Telegram" \
        2 "Masukkan Chat ID Telegram" \
        3 "Masukkan Folder yang ingin di-backup" \
        4 "Konfigurasi MySQL Multi Instance" \
        5 "Aktifkan PostgreSQL Backup" \
        6 "Retention (hari)" \
        7 "Timezone Server" \
        8 "Jadwal Backup (systemd timer)" \
        9 "Selesai & Install" \
        0 "Keluar" 2> /tmp/menu_choice

    case $(cat /tmp/menu_choice) in
        1) set_token ;;
        2) set_chatid ;;
        3) set_folders ;;
        4) set_mysql_menu ;;
        5) set_pg ;;
        6) set_retention ;;
        7) set_timezone ;;
        8) set_cron ;;
        9) finalize_install ;;
        0) clear; exit 0 ;;
    esac

    menu_installer
}

# --------------------------------------------
#  INPUT FUNCTIONS
# --------------------------------------------
set_token() {
    BOT_TOKEN=$(dialog --inputbox "Masukkan BOT TOKEN Telegram:" 10 60 "$BOT_TOKEN" 2>&1 >/dev/tty)
}
set_chatid() {
    CHAT_ID=$(dialog --inputbox "Masukkan CHAT ID Telegram:" 10 60 "$CHAT_ID" 2>&1 >/dev/tty)
}
set_folders() {
    FOLDERS_RAW=$(dialog --inputbox "Masukkan folder (pisahkan dengan koma):" 10 60 "$FOLDERS_RAW" 2>&1 >/dev/tty)
}
set_pg() {
    USE_PG=$(dialog --menu "Backup PostgreSQL?" 12 40 2 \
        y "Ya" n "Tidak" 2>&1 >/dev/tty)
}
set_retention() {
    RETENTION_DAYS=$(dialog --inputbox "Berapa hari file backup disimpan?" 10 60 "$RETENTION_DAYS" 2>&1 >/dev/tty)
}
set_timezone() {
    TZ=$(dialog --inputbox "Timezone (contoh: Asia/Jakarta):" 10 60 "$TZ" 2>&1 >/dev/tty)
}
set_cron() {
    CRON_TIME=$(dialog --inputbox "Jadwal systemd (contoh: *-*-* 03:00:00):" 10 60 "$CRON_TIME" 2>&1 >/dev/tty)
}

# --------------------------------------------
# MYSQL MENU
# --------------------------------------------
set_mysql_menu() {
    dialog --menu "Backup MySQL?" 12 40 2 \
        y "Ya" n "Tidak" 2> /tmp/mysql_choice

    USE_MYSQL=$(cat /tmp/mysql_choice)

    [[ $USE_MYSQL == "n" ]] && MYSQL_MULTI_CONF="" && return

    while true; do
        dialog --menu "Menu MySQL Multi Instance" 15 60 6 \
            1 "Tambah konfigurasi MySQL" \
            2 "Lihat konfigurasi" \
            3 "Hapus konfigurasi" \
            0 "Kembali" 2> /tmp/mysql_menu

        case $(cat /tmp/mysql_menu) in
            1) add_mysql_config ;;
            2) show_mysql ;;
            3) remove_mysql ;;
            0) break ;;
        esac
    done
}

add_mysql_config() {
    MYSQL_HOST=$(dialog --inputbox "MySQL Host:" 10 60 "localhost" 2>&1 >/dev/tty)
    MYSQL_USER=$(dialog --inputbox "MySQL Username:" 10 60 2>&1 >/dev/tty)
    MYSQL_PASS=$(dialog --passwordbox "MySQL Password:" 10 60 2>&1 >/dev/tty)

    MODE=$(dialog --menu "Mode database:" 12 40 2 \
        all "Semua database" \
        pilih "Pilih database" 2>&1 >/dev/tty)

    if [[ $MODE == "pilih" ]]; then
        DBLIST=$(dialog --inputbox "Masukkan nama DB (comma separated):" 10 60 2>&1 >/dev/tty)
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
    dialog --msgbox "Konfigurasi MySQL:\n\n$MYSQL_MULTI_CONF\n\nBranding: Hendri Backup System" 20 70
}

remove_mysql() {
    IFS=';' read -ra ARR <<< "$MYSQL_MULTI_CONF"
    LIST=()
    num=1
    for item in "${ARR[@]}"; do
        LIST+=($num "$item")
        ((num++))
    done

    CHOICE=$(dialog --menu "Hapus konfigurasi:" 20 70 10 "${LIST[@]}" 2>&1 >/dev/tty)
    [[ -z $CHOICE ]] && return

    unset 'ARR[CHOICE-1]'
    MYSQL_MULTI_CONF=$(IFS=';'; echo "${ARR[*]}")
}

# --------------------------------------------
#  FINAL INSTALL PROCESS
# --------------------------------------------
finalize_install() {

dialog --infobox "Sedang menyimpan konfigurasi...\nWatermark by Hendri" 5 50
sleep 1

cat <<EOF > "$CONFIG_FILE"
# Konfigurasi Backup VPS Telegram
# Watermark by Hendri — Support: t.me/hendrichat
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

# --------------------------------------------
# BACKUP RUNNER SCRIPT
# --------------------------------------------
cat <<'EOF' > "$BACKUP_RUNNER"
#!/bin/bash
# Auto Backup Runner — Watermark by Hendri

CONFIG_FILE="/opt/auto-backup/config.conf"
source "$CONFIG_FILE"

BACKUP_DIR="$INSTALL_DIR/backups"
mkdir -p "$BACKUP_DIR"

DATE=$(date +%F-%H%M)
FILE="$BACKUP_DIR/backup-$DATE.tar.gz"
TMP_DIR="$INSTALL_DIR/tmp-$DATE"
mkdir -p "$TMP_DIR"

# Copy folders
IFS=',' read -ra FL <<< "$FOLDERS_RAW"
for f in "${FL[@]}"; do [[ -d "$f" ]] && cp -r "$f" "$TMP_DIR/"; done

# MySQL dump
if [[ "$USE_MYSQL" == "y" ]]; then
    mkdir -p "$TMP_DIR/mysql"
    IFS=';' read -ra MYSQLS <<< "$MYSQL_MULTI_CONF"
    for item in "${MYSQLS[@]}"; do
        USERPASS=$(echo "$item" | cut -d'@' -f1)
        HOSTDB=$(echo "$item" | cut -d'@' -f2)
        USER=$(echo "$USERPASS" | cut -d':' -f1)
        PASS=$(echo "$USERPASS" | cut -d':' -f2)
        HOST=$(echo "$HOSTDB" | cut -d':' -f1)
        DBS=$(echo "$HOSTDB" | cut -d':' -f2)
        ARG="-h$HOST -u$USER -p$PASS"

        if [[ "$DBS" == "all" ]]; then
            mysqldump $ARG --all-databases > "$TMP_DIR/mysql/${USER}@${HOST}_ALL.sql"
        else
            IFS=',' read -ra DBARR <<< "$DBS"
            for db in "${DBARR[@]}"; do
                mysqldump $ARG "$db" > "$TMP_DIR/mysql/${USER}@${HOST}_${db}.sql"
            done
        fi
    done
fi

# PostgreSQL dump
if [[ "$USE_PG" == "y" ]]; then
    mkdir -p "$TMP_DIR/postgres"
    su - postgres -c "pg_dumpall > $TMP_DIR/postgres/all.sql"
fi

tar -czf "$FILE" -C "$TMP_DIR" .

curl -s -F document=@"$FILE" \
    -F caption="Backup selesai: $(basename $FILE)\nPowered by Hendri Backup System" \
    "https://api.telegram.org/bot$BOT_TOKEN/sendDocument?chat_id=$CHAT_ID"

rm -rf "$TMP_DIR"
find "$BACKUP_DIR" -type f -mtime +$RETENTION_DAYS -delete
EOF

chmod +x "$BACKUP_RUNNER"

# --------------------------------------------
# SYSTEMD SERVICE & TIMER
# --------------------------------------------
cat <<EOF > /etc/systemd/system/auto-backup.service
[Unit]
Description=Auto Backup VPS to Telegram
After=network.target mysql.service mariadb.service postgresql.service

[Service]
Type=oneshot
ExecStart=$BACKUP_RUNNER
User=root
Environment=TZ=$TZ

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

# --------------------------------------------
# GLOBAL MENU LAUNCHER
# --------------------------------------------
cat <<'EOF' > /usr/bin/menu-bot-backup
#!/bin/bash
bash /opt/auto-backup/menu.sh
EOF
chmod +x /usr/bin/menu-bot-backup

# --------------------------------------------
# CONTROL PANEL MENU
# --------------------------------------------
cat <<'EOF' > /opt/auto-backup/menu.sh
#!/bin/bash
CONFIG="/opt/auto-backup/config.conf"
source "$CONFIG"

while true; do
    dialog --clear --menu "AUTO BACKUP TELEGRAM — MENU PRO\nWatermark by Hendri" 22 70 12 \
        1 "Lihat konfigurasi" \
        2 "Ubah folder backup" \
        3 "Kelola MySQL" \
        4 "Ganti Timezone" \
        5 "Ganti Retention" \
        6 "Jalankan backup sekarang" \
        0 "Keluar" 2> /tmp/pil

    case $(cat /tmp/pil) in
        1) dialog --msgbox "`cat $CONFIG`" 25 80 ;;
        2) nano $CONFIG ;;
        3) nano $CONFIG ;;
        4) nano $CONFIG ;;
        5) nano $CONFIG ;;
        6) bash /opt/auto-backup/backup-runner.sh && dialog --msgbox "Backup selesai & terkirim!\nPowered by Hendri" 10 50 ;;
        0) clear; exit 0 ;;
    esac
done
EOF

chmod +x /opt/auto-backup/menu.sh

dialog --msgbox "INSTALL COMPLETE!\n\nGunakan perintah:\n   menu-bot-backup\n\nPowered by Hendri Backup System" 12 50

clear
exit 0
}

# --------------------------------------------
# START INSTALLER
# --------------------------------------------
menu_installer
