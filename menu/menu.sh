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

# Writing remaining files and zipping...
    read -p "Mode DB? 1=ALL, 2=Pilih: " M
    if [[ "$M" == "1" ]]; then
        DB="all"
    else
        read -p "List DB (comma): " DB
    fi

    NEW="${U}:${P}@${H}:${DB}"

    [[ -z "$MYSQL_MULTI_CONF" ]] && MYSQL_MULTI_CONF="$NEW" || MYSQL_MULTI_CONF="$MYSQL_MULTI_CONF;$NEW"

    echo "[OK] MySQL config ditambahkan."
}

edit_mysql() {
    if [[ -z "$MYSQL_MULTI_CONF" ]]; then echo "Tidak ada konfigurasi MySQL."; return; fi
    IFS=';' read -r -a LIST <<< "$MYSQL_MULTI_CONF"
    for i in "${!LIST[@]}"; do printf "%2d) %s
" $((i+1)) "${LIST[$i]}"; done
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
    IFS=';' read -r -a LIST <<< "$MYSQL_MULTI_CONF"
    for i in "${!LIST[@]}"; do printf "%2d) %s
" $((i+1)) "${LIST[$i]}"; done
    read -p "Pilih nomor yang ingin dihapus: " NUM
    if ! [[ "$NUM" =~ ^[0-9]+$ ]] || (( NUM < 1 || NUM > ${#LIST[@]} )); then echo "Pilihan invalid."; return; fi
    unset 'LIST[NUM-1]'
    MYSQL_MULTI_CONF=$(IFS=';'; echo "${LIST[*]}")
    echo "[OK] Dihapus."
}

# MongoDB functions (continuation)
add_mongo() {
    read -p "Host (default: localhost): " H; H=${H:-localhost}
    read -p "Port (default: 27017): " PORT; PORT=${PORT:-27017}
    read -p "User (kosong=tanpa auth): " U
    if [[ -n "$U" ]]; then
        read -s -p "Pass: " P; echo ""
        read -p "Auth DB (default admin): " A; A=${A:-admin}
    else
        P=""
        A=""
    fi
    read -p "Mode DB? 1=ALL 2=pilih: " M
    if [[ "$M" == "1" ]]; then DB="all"; else read -p "List DB (comma): " DB; fi
    NEW="${U}:${P}@${H}:${PORT}:${A}:${DB}"
    [[ -z "$MONGO_MULTI_CONF" ]] && MONGO_MULTI_CONF="$NEW" || MONGO_MULTI_CONF="$MONGO_MULTI_CONF;$NEW"
    echo "[OK] MongoDB config ditambahkan."
}

edit_mongo() {
    if [[ -z "$MONGO_MULTI_CONF" ]]; then echo "Tidak ada konfigurasi MongoDB."; return; fi
    IFS=';' read -r -a LIST <<< "$MONGO_MULTI_CONF"
    for i in "${!LIST[@]}"; do printf "%2d) %s
" $((i+1)) "${LIST[$i]}"; done
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
    IFS=';' read -r -a LIST <<< "$MONGO_MULTI_CONF"
    for i in "${!LIST[@]}"; do printf "%2d) %s
" $((i+1)) "${LIST[$i]}"; done
    read -p "Pilih nomor yang ingin dihapus: " NUM
    if ! [[ "$NUM" =~ ^[0-9]+$ ]] || (( NUM < 1 || NUM > ${#LIST[@]} )); then echo "Pilihan invalid."; return; fi
    unset 'LIST[NUM-1]'
    MONGO_MULTI_CONF=$(IFS=';'; echo "${LIST[*]}")
    echo "[OK] Dihapus."
}

# Remaining menu functions (timezone, retention, oncalendar, test, restore, encrypt, rebuild, toggles)
change_timezone() {
    read -p "Masukkan timezone (contoh: Asia/Jakarta): " NEWTZ
    if [[ -z "$NEWTZ" ]]; then echo "Tidak ada perubahan."; return; fi
    TZ="$NEWTZ"
    echo "[INFO] Setting timezone sistem => $TZ"
    timedatectl set-timezone "$TZ" 2>/dev/null || echo "[WARN] timedatectl mungkin gagal (tidak root)"
    echo "[OK] Timezone set to $TZ"
}

change_retention() {
    read -p "Masukkan retention days (current: $RETENTION_DAYS): " R
    if [[ -z "$R" ]]; then echo "Tidak ada perubahan."; return; fi
    RETENTION_DAYS="$R"
    echo "[OK] Retention set to $RETENTION_DAYS"
}

build_oncalendar() {
    echo "Bentuk OnCalendar: '*-*-* HH:MM:SS' (daily), atau 'Mon *-*-* HH:MM:SS' (weekly) dsb."
    read -p "Masukkan string OnCalendar: " OC
    if [[ -z "$OC" ]]; then echo "Tidak ada input."; return; fi
    if [[ -x "$BASE_DIR/systemd/timer.sh" ]]; then
        bash "$BASE_DIR/systemd/timer.sh" "$OC"
        echo "[OK] OnCalendar disimpan: $OC"
    else
        cat > "$TIMER_FILE" <<EOF
[Unit]
Description=Run Auto Backup VPS

[Timer]
OnCalendar=$OC
Persistent=true
Unit=auto-backup.service

[Install]
WantedBy=timers.target
EOF
        systemctl daemon-reload
        systemctl enable --now auto-backup.timer || true
        echo "[OK] Timer updated (fallback): $OC"
    fi
}

test_backup() {
    echo "[OK] Menjalan backup-runner..."
    bash "$RUNNER"
    echo "Backup selesai."
}

restore_backup() {
    echo "Daftar backup:"
    files=($(ls -1t "$INSTALL_DIR/backups" 2>/dev/null))
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

encrypt_last_backup() {
    mkdir -p "$INSTALL_DIR/backups"
    LAST=$(ls -1t "$INSTALL_DIR/backups" 2>/dev/null | head -n1)
    if [[ -z "$LAST" ]]; then echo "Tidak ada backup untuk diencrypt."; return; fi
    read -s -p "Masukkan password enkripsi: " PWD; echo ""
    OUT="$INSTALL_DIR/backups/${LAST%.*}.zip"
    if command -v zip >/dev/null 2>&1; then
        zip -P "$PWD" "$OUT" "$INSTALL_DIR/backups/$LAST" >/dev/null 2>&1
        echo "Encrypted archive dibuat: $OUT"
    else
        echo "Perintah zip tidak tersedia. Install zip lalu ulangi."
    fi
}

rebuild_installer_files() {
    echo "[INFO] Membangun ulang runner / systemd files berdasarkan config..."
    if [[ -x "$BASE_DIR/runner/backup-runner.sh" ]]; then
        bash "$BASE_DIR/runner/backup-runner.sh" --build || true
    fi
    if [[ -x "$BASE_DIR/systemd/service.sh" ]]; then
        bash "$BASE_DIR/systemd/service.sh" || true
    fi
    CRON_TIME="${CRON_TIME:-*-*-* 03:00:00}"
    if [[ -x "$BASE_DIR/systemd/timer.sh" ]]; then
        bash "$BASE_DIR/systemd/timer.sh" "$CRON_TIME" || true
    fi
    systemctl daemon-reload || true
    systemctl enable --now auto-backup.timer || true
    systemctl enable auto-backup.service || true
    echo "[OK] Rebuild complete."
}

restart_service_timer() {
    systemctl restart auto-backup.timer || true
    systemctl restart auto-backup.service || true
    echo "[OK] Service & Timer restarted."
}

toggle_mysql() {
    echo "Status sekarang USE_MYSQL = $USE_MYSQL"
    read -p "Aktifkan MySQL? (y/n): " jawab
    case "$jawab" in
        y|Y) USE_MYSQL="y"; echo "[OK] MySQL DI-AKTIFKAN." ;;
        n|N) USE_MYSQL="n"; echo "[OK] MySQL DI-MATIKAN." ;;
        *) echo "Input tidak valid. Gunakan y atau n."; return ;;
    esac
    save_config
}

toggle_mongo() {
    echo "Status sekarang USE_MONGO = $USE_MONGO"
    read -p "Aktifkan MongoDB? (y/n): " jawab
    case "$jawab" in
        y|Y) USE_MONGO="y"; echo "[OK] MongoDB DI-AKTIFKAN." ;;
        n|N) USE_MONGO="n"; echo "[OK] MongoDB DI-MATIKAN." ;;
        *) echo "Input tidak valid. Gunakan y atau n."; return ;;
    esac
    save_config
}

toggle_pg() {
    echo "Status sekarang USE_PG = $USE_PG"
    read -p "Aktifkan PostgreSQL? (y/n): " jawab
    case "$jawab" in
        y|Y) USE_PG="y"; echo "[OK] PostgreSQL DI-AKTIFKAN." ;;
        n|N) USE_PG="n"; echo "[OK] PostgreSQL DI-MATIKAN." ;;
        *) echo "Input tidak valid. Gunakan y atau n."; return ;;
    esac
    save_config
}

# Main menu loop
while true; do
    clear
    echo "$HEADER"
    echo ""
    echo "1) Lihat konfigurasi"
    echo "2) Edit BOT TOKEN"
    echo "3) Edit CHAT ID"
    echo "4) Tambah Folder Backup"
    echo "5) Hapus Folder Backup"
    echo "6) Tambah konfigurasi MySQL"
    echo "7) Edit konfigurasi MySQL"
    echo "8) Hapus konfigurasi MySQL"
    echo "9) Tambah konfigurasi MongoDB"
    echo "10) Edit konfigurasi MongoDB"
    echo "11) Hapus konfigurasi MongoDB"
    echo "12) Edit PostgreSQL settings & test dump"
    echo "13) Ubah Timezone"
    echo "14) Ubah Retention Days"
    echo "15) Ubah Jadwal Backup (OnCalendar helper)"
    echo "16) Test backup sekarang"
    echo "17) Restore dari backup"
    echo "18) Rebuild / Repair installer files (service/timer/runner)"
    echo "19) Encrypt latest backup (zip with password)"
    echo "20) Restart service & timer"
    echo "21) Simpan config"
    echo "22) Status (service / last backup / next run)"
    echo "23) Status Realtime (live monitor)"
    echo "24) Gunakan MySQL (use_mysql)"
    echo "25) Gunakan MongoDB (use_mongo)"
    echo "26) Gunakan PostgreSQL (use_pg)"
    echo "0) Keluar"
    echo ""
    read -p "Pilih menu: " opt

    case $opt in
        1) cat "$CONFIG"; pause ;;
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
        13) change_timezone; pause ;;
        14) change_retention; pause ;;
        15) build_oncalendar; pause ;;
        16) test_backup; pause ;;
        17) restore_backup; pause ;;
        18) if confirm "Anda yakin ingin (re)build installer files?"; then rebuild_installer_files; fi; pause ;;
        19) encrypt_last_backup; pause ;;
        20) restart_service_timer; pause ;;
        21) save_config; pause ;;
        22) show_status ;;
        23) show_status_live ;;
        24) toggle_mysql ;;
        25) toggle_mongo ;;
        26) toggle_pg ;;
        0) echo "Keluar"; break ;;
        *) echo "Invalid"; sleep 1 ;;
    esac
done

exit 0
