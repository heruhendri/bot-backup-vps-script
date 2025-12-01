#!/bin/bash
CONFIG="/opt/auto-backup/config.conf"
INSTALL_DIR="/opt/auto-backup"
RUNNER="$INSTALL_DIR/backup-runner.sh"

if [[ ! -f "$CONFIG" ]]; then
    echo "Config tidak ditemukan. Jalankan installer terlebih dahulu."
    exit 1
fi

source "$CONFIG"

# ===============================
#  FUNCTION: SHOW MENU
# ===============================
show_menu() {
    clear
    echo "================================================="
    echo "   CONFIG MANAGER — AUTO BACKUP TELEGRAM VPS"
    echo "================================================="
    echo ""
    echo "BOT Token       : $BOT_TOKEN"
    echo "Chat ID         : $CHAT_ID"
    echo "Timezone        : $TZ"
    echo "Retention       : $RETENTION_DAYS hari"
    echo ""

    echo "Folder Backup:"
    if [[ -z "$FOLDERS_RAW" ]]; then
        echo "  (kosong)"
    else
        echo "  $FOLDERS_RAW"
    fi

    echo ""
    echo "MySQL Config:"
    if [[ -z "$MYSQL_MULTI_CONF" ]]; then
        echo "  (tidak ada konfigurasi)"
    else
        IFS=';' read -ra LIST <<< "$MYSQL_MULTI_CONF"
        i=1
        for item in "${LIST[@]}"; do
            echo "  [$i] $item"
            ((i++))
        done
    fi

    echo ""
    echo "==================== MENU ======================="
    echo "1) Tambah folder backup"
    echo "2) Hapus folder backup"
    echo "3) Tambah konfigurasi MySQL"
    echo "4) Hapus konfigurasi MySQL"
    echo "5) Simpan perubahan & keluar"
    echo "-----------------------"
    echo "6) Ubah BOT TOKEN"
    echo "7) Ubah CHAT ID"
    echo "8) Ubah timezone"
    echo "9) Ubah retention"
    echo "10) Ubah jadwal backup"
    echo "11) Lihat file config"
    echo "12) Test backup sekarang"
    echo "13) Restart systemd service/timer"
    echo "0) Keluar tanpa menyimpan"
    echo "================================================="
}

# ===============================
#  SAVE CONFIG
# ===============================
save_config() {
cat <<EOF > "$CONFIG"
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

echo ""
echo "[OK] Konfigurasi berhasil disimpan!"
exit 0
}

# ===============================
#  ADD FOLDER
# ===============================
add_folder() {
    read -p "Masukkan folder baru (comma separated): " NEW_FOLDER
    if [[ -z "$FOLDERS_RAW" ]]; then
        FOLDERS_RAW="$NEW_FOLDER"
    else
        FOLDERS_RAW="$FOLDERS_RAW,$NEW_FOLDER"
    fi
    echo "[OK] Folder berhasil ditambahkan!"
}

# ===============================
#  DELETE FOLDER
# ===============================
delete_folder() {
    if [[ -z "$FOLDERS_RAW" ]]; then
        echo "Tidak ada folder yang bisa dihapus."
        return
    fi

    echo ""
    echo "Pilih folder untuk dihapus:"
    IFS=',' read -ra FL <<< "$FOLDERS_RAW"

    i=1
    for f in "${FL[@]}"; do
        echo "$i) $f"
        ((i++))
    done

    read -p "Pilih nomor: " NUM
    if (( NUM < 1 || NUM > ${#FL[@]} )); then
        echo "Pilihan tidak valid!"
        return
    fi

    unset 'FL[NUM-1]'
    FOLDERS_RAW=$(IFS=','; echo "${FL[*]}")

    echo "[OK] Folder dihapus!"
}

# ===============================
#  ADD MYSQL
# ===============================
add_mysql() {
    echo "Tambah konfigurasi MySQL baru:"
    read -p "MySQL Host (default: localhost): " MYSQL_HOST
    MYSQL_HOST=${MYSQL_HOST:-localhost}

    read -p "MySQL Username: " MYSQL_USER
    read -s -p "MySQL Password: " MYSQL_PASS
    echo ""

    echo "Mode database:"
    echo "1) Semua database"
    echo "2) Pilih database"
    read -p "Pilih: " MODE

    if [[ "$MODE" == "1" ]]; then
        DB="all"
    else
        read -p "Masukkan nama database (comma separated): " DB
    fi

    NEW_ENTRY="${MYSQL_USER}:${MYSQL_PASS}@${MYSQL_HOST}:${DB}"

    if [[ -z "$MYSQL_MULTI_CONF" ]]; then
        MYSQL_MULTI_CONF="$NEW_ENTRY"
    else
        MYSQL_MULTI_CONF="$MYSQL_MULTI_CONF;$NEW_ENTRY"
    fi

    echo "[OK] MySQL config berhasil ditambahkan!"
}

# ===============================
#  DELETE MYSQL
# ===============================
delete_mysql() {
    if [[ -z "$MYSQL_MULTI_CONF" ]]; then
        echo "Tidak ada konfigurasi MySQL yang bisa dihapus."
        return
    fi

    IFS=';' read -ra LIST <<< "$MYSQL_MULTI_CONF"
    echo "Pilih konfigurasi untuk dihapus:"
    i=1
    for item in "${LIST[@]}"; do
        echo "$i) $item"
        ((i++))
    done

    read -p "Nomor yang ingin dihapus: " NUM
    if (( NUM < 1 || NUM > ${#LIST[@]} )); then
        echo "Pilihan tidak valid!"
        return
    fi

    unset 'LIST[NUM-1]'
    MYSQL_MULTI_CONF=$(IFS=';'; echo "${LIST[*]}")

    echo "[OK] MySQL config dihapus!"
}

# ===============================
#  NEW FEATURES
# ===============================

edit_token() {
    read -p "Masukkan BOT TOKEN baru: " BOT_TOKEN
    echo "[OK] BOT TOKEN diperbarui!"
}

edit_chatid() {
    read -p "Masukkan CHAT ID baru: " CHAT_ID
    echo "[OK] CHAT ID diperbarui!"
}

edit_timezone() {
    read -p "Masukkan timezone baru (ex: Asia/Jakarta): " TZ
    timedatectl set-timezone "$TZ"
    echo "[OK] Timezone berhasil diganti!"
}

edit_retention() {
    read -p "Masukkan jumlah hari retention baru: " RETENTION_DAYS
    echo "[OK] Retention diperbarui!"
}

edit_schedule() {
    read -p "Masukkan jadwal baru (format systemd: *-*-* 03:00:00): " SCH
    sed -i "s|OnCalendar=.*|OnCalendar=$SCH|g" /etc/systemd/system/auto-backup.timer
    systemctl daemon-reload
    systemctl restart auto-backup.timer
    echo "[OK] Jadwal backup diperbarui!"
}

show_config_file() {
    echo "================ CONFIG FILE ================"
    cat "$CONFIG"
    echo "============================================"
}

test_backup() {
    echo "[OK] Menjalankan backup..."
    bash "$RUNNER"
    echo "Selesai!"
}

restart_services() {
    systemctl daemon-reload
    systemctl restart auto-backup.service
    systemctl restart auto-backup.timer
    echo "[OK] Service & timer direstart."
}

# ===============================
#  MAIN LOOP
# ===============================
while true; do
    show_menu
    read -p "Pilih menu: " menu

    case $menu in
        1) add_folder ;;
        2) delete_folder ;;
        3) add_mysql ;;
        4) delete_mysql ;;
        5) save_config ;;   # EXIT
        6) edit_token ;;
        7) edit_chatid ;;
        8) edit_timezone ;;
        9) edit_retention ;;
        10) edit_schedule ;;
        11) show_config_file ;;
        12) test_backup ;;
        13) restart_services ;;
        0) exit 0 ;;
        *) echo "Pilihan tidak valid!" ;;
    esac

    echo ""
    read -p "Tekan ENTER untuk melanjutkan..."
done
