#!/bin/bash
set -euo pipefail

CONFIG="/opt/auto-backup/config.conf"
BASE_DIR="/opt/auto-backup"
RUNNER="$BASE_DIR/runner/backup-runner.sh"
LOGFILE="$BASE_DIR/menu.log"
SERVICE_FILE="/etc/systemd/system/auto-backup.service"
TIMER_FILE="/etc/systemd/system/auto-backup.timer"

HEADER="===============================================
      AUTO BACKUP VPS — MENU PRO
      Script by Hendri
      Support: t.me/GbtTapiPngnSndiri
==============================================="

FOOTER="===============================================
 Script by Hendri — Auto Backup VPS
 Support: t.me/GbtTapiPngnSndiri
==============================================="

# ---------------------------------------------------
# Load Config
# ---------------------------------------------------
if [[ ! -f "$CONFIG" ]]; then
    echo "Config tidak ditemukan di $CONFIG"
    exit 1
fi

source "$CONFIG"

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

# ---------------------------------------------------
# Helper
# ---------------------------------------------------
pause() { read -p "Tekan ENTER untuk lanjut..."; }

confirm() {
    read -p "$1 (y/N): " ans
    [[ "$ans" =~ ^[Yy]$ ]]
}

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
echo "[OK] Config disimpan." | tee -a "$LOGFILE"
}

reload_systemd() {
    systemctl daemon-reload
    systemctl restart auto-backup.timer || true
    systemctl restart auto-backup.service || true
    echo "[OK] Systemd direload." | tee -a "$LOGFILE"
}

# ---------------------------------------------------
# STATUS (STATIC)
# ---------------------------------------------------
show_status() {
    clear
    echo "$HEADER"
    echo ""

    echo "Service:  $(systemctl is-active auto-backup.service) (enabled: $(systemctl is-enabled auto-backup.service))"
    echo "Timer:    $(systemctl is-active auto-backup.timer) (enabled: $(systemctl is-enabled auto-backup.timer))"

    next=$(systemctl list-timers --all | grep auto-backup.timer | awk '{print $1,$2,$3}')
    echo "Next Run: ${next:-Tidak tersedia}"

    LAST=$(ls -1t "$INSTALL_DIR/backups" 2>/dev/null | head -n1)
    if [[ -n "$LAST" ]]; then
        T=$(stat -c "%y" "$INSTALL_DIR/backups/$LAST" | cut -d'.' -f1)
        echo "Last Backup: $LAST ($T)"
    else
        echo "Last Backup: (belum ada)"
    fi

    echo ""
    echo "--- 5 Baris Log Terakhir ---"
    journalctl -u auto-backup.service -n 5 --no-pager

    pause
}

# ---------------------------------------------------
# STATUS LIVE
# ---------------------------------------------------
show_status_live() {
    trap 'tput cnorm; clear; echo "Keluar dari realtime."' SIGINT
    tput civis

    while true; do
        clear
        echo "$HEADER"
        echo "Realtime Monitor (refresh 1 detik)"
        echo ""

        svc=$(systemctl is-active auto-backup.service)
        tmr=$(systemctl is-active auto-backup.timer)
        echo "Service: $svc"
        echo "Timer:   $tmr"

        NEXT=$(systemctl list-timers --all | grep auto-backup.timer | awk '{print $1,$2,$3}')
        echo "Next Run: ${NEXT:-Tidak tersedia}"

        LAST=$(ls -1t "$INSTALL_DIR/backups" 2>/dev/null | head -n1)
        if [[ -n "$LAST" ]]; then
            T=$(stat -c "%y" "$INSTALL_DIR/backups/$LAST" | cut -d'.' -f1)
            echo "Last Backup: $LAST ($T)"
        else
            echo "Last Backup: (belum ada)"
        fi

        echo ""
        echo "--- Log (3 baris terakhir) ---"
        journalctl -u auto-backup.service -n 3 --no-pager
        sleep 1
    done

    tput cnorm
}

# ---------------------------------------------------
# Folder Manager
# ---------------------------------------------------
add_folder() {
    read -p "Masukkan folder tambahan: " F
    [[ -z "$F" ]] && { echo "Input kosong."; return; }

    if [[ -z "$FOLDERS_RAW" ]]; then
        FOLDERS_RAW="$F"
    else
        FOLDERS_RAW="$FOLDERS_RAW,$F"
    fi

    echo "[OK] Ditambahkan: $F"
}

delete_folder() {
    [[ -z "$FOLDERS_RAW" ]] && { echo "Tidak ada folder."; return; }

    IFS=',' read -r -a arr <<< "$FOLDERS_RAW"
    echo "Daftar folder:"
    for i in "${!arr[@]}"; do
        echo "$((i+1))) ${arr[$i]}"
    done

    read -p "Pilih nomor: " N
    if ! [[ $N =~ ^[0-9]+$ ]]; then echo "Invalid."; return; fi
    (( N-- ))

    unset 'arr[N]'
    FOLDERS_RAW=$(IFS=','; echo "${arr[*]}")
    echo "[OK] Folder dihapus."
}

# ---------------------------------------------------
# MySQL Manager
# ---------------------------------------------------
list_mysql() {
    if [[ -z "$MYSQL_MULTI_CONF" ]]; then
        echo "(Tidak ada konfigurasi)"
        return
    fi
    IFS=';' read -r -a arr <<< "$MYSQL_MULTI_CONF"
    for i in "${!arr[@]}"; do
        echo "$((i+1))) ${arr[$i]}"
    done
}

add_mysql() {
    read -p "Host (default: localhost): " H; H=${H:-localhost}
    read -p "User: " U
    read -s -p "Pass: " P; echo ""

    echo "Mode DB? 1=ALL, 2=Pilih"
    read -p "> " M
    if [[ "$M" == "1" ]]; then
        DB="all"
    else
        read -p "List DB (comma): " DB
    fi

    NEW="${U}:${P}@${H}:${DB}"

    [[ -z "$MYSQL_MULTI_CONF" ]] && MYSQL_MULTI_CONF="$NEW" || MYSQL_MULTI_CONF="$MYSQL_MULTI_CONF;$NEW"

    echo "[OK] MySQL config ditambahkan."
}

# ---------------------------------------------------
# Mongo Manager
# ---------------------------------------------------
list_mongo() {
    if [[ -z "$MONGO_MULTI_CONF" ]]; then
        echo "(Tidak ada konfigurasi MongoDB)"
        return
    fi

    IFS=';' read -r -a arr <<< "$MONGO_MULTI_CONF"
    for i in "${!arr[@]}"; do echo "$((i+1))) ${arr[$i]}"; done
}

add_mongo() {
    read -p "Host (default: localhost): " H; H=${H:-localhost}
    read -p "Port (default: 27017): " PORT; PORT=${PORT:-27017}
    read -p "User (kosong=tanpa auth): " U
    if [[ -n "$U" ]]; then
        read -s -p "Password: " P; echo ""
        read -p "Auth DB (default admin): " A; A=${A:-admin}
    else
        P=""; A=""
    fi

    echo "Mode DB? 1 = ALL, 2 = pilih"
    read -p "> " M
    if [[ "$M" == "1" ]]; then DB="all"; else read -p "List DB (comma): " DB; fi

    NEW="${U}:${P}@${H}:${PORT}:${A}:${DB}"

    [[ -z "$MONGO_MULTI_CONF" ]] && MONGO_MULTI_CONF="$NEW" || MONGO_MULTI_CONF="$MONGO_MULTI_CONF;$NEW"

    echo "[OK] MongoDB config ditambahkan."
}

# ---------------------------------------------------
# Backup
# ---------------------------------------------------
test_backup() {
    echo "[INFO] Menjalan backup-runner..."
    bash "$RUNNER"
    echo "Backup selesai."
}

restore_backup() {
    echo "Daftar backup:"
    files=($(ls -1t "$INSTALL_DIR/backups"))
    for i in "${!files[@]}"; do
        echo "$((i+1))) ${files[$i]}"
    done

    read -p "Pilih file: " N
    ((N--))
    FILE="${files[$N]}"

    echo "Preview isi:"
    tar -tzf "$INSTALL_DIR/backups/$FILE" | sed -n '1,20p'

    if ! confirm "Lanjut restore ke / ?"; then
        echo "Batal."
        return
    fi

    TMP="$BASE_DIR/tmp_restore_$(date +%s)"
    mkdir -p "$TMP"
    tar -xzf "$INSTALL_DIR/backups/$FILE" -C "$TMP"

    rsync -a "$TMP"/ /
    rm -rf "$TMP"

    echo "[OK] Restore selesai."
}

# ---------------------------------------------------
# MAIN MENU
# ---------------------------------------------------
while true; do
    clear
    echo "$HEADER"
    echo ""
    echo "1) Lihat Config"
    echo "2) Edit BOT TOKEN"
    echo "3) Edit CHAT ID"
    echo "4) Tambah Folder Backup"
    echo "5) Hapus Folder Backup"
    echo "6) List MySQL Config"
    echo "7) Tambah MySQL Config"
    echo "8) List MongoDB Config"
    echo "9) Tambah MongoDB Config"
    echo "10) Ubah Timezone"
    echo "11) Ubah Retention"
    echo "12) Test Backup"
    echo "13) Restore Backup"
    echo "14) Reload Systemd"
    echo "15) Status (Static)"
    echo "16) Status (Realtime)"
    echo "17) Simpan Config"
    echo "0) Keluar"
    echo ""

    read -p "Pilih menu: " M

    case $M in
        1) cat "$CONFIG"; pause ;;
        2) read -p "BOT TOKEN baru: " BOT_TOKEN ;;
        3) read -p "CHAT ID baru: " CHAT_ID ;;
        4) add_folder ;;
        5) delete_folder ;;
        6) list_mysql; pause ;;
        7) add_mysql ;;
        8) list_mongo; pause ;;
        9) add_mongo ;;
        10) read -p "Timezone baru: " TZ; timedatectl set-timezone "$TZ" ;;
        11) read -p "Retention days: " RETENTION_DAYS ;;
        12) test_backup; pause ;;
        13) restore_backup; pause ;;
        14) reload_systemd; pause ;;
        15) show_status ;;
        16) show_status_live ;;
        17) save_config ;;
        0) exit 0 ;;
        *) echo "Invalid"; sleep 1 ;;
    esac
done

exit 0
