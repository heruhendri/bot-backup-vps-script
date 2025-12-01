#!/bin/bash
# PRO Menu for Auto Backup VPS — TELEGRAM BOT
# Location expected: /opt/auto-backup/menu.sh
# Requires: bash, tar, timedatectl, systemctl, mysqldump (optional), pg_dumpall (optional), unzip (optional), zip (optional)

CONFIG="/opt/auto-backup/config.conf"
INSTALL_DIR="/opt/auto-backup"
RUNNER="$INSTALL_DIR/backup-runner.sh"
SERVICE_FILE="/etc/systemd/system/auto-backup.service"
TIMER_FILE="/etc/systemd/system/auto-backup.timer"
LOGFILE="$INSTALL_DIR/menu-pro.log"

# Ensure config exists
if [[ ! -f "$CONFIG" ]]; then
    echo "Config tidak ditemukan di $CONFIG. Jalankan installer terlebih dahulu." | tee -a "$LOGFILE"
    exit 1
fi

# load config (safe)
source "$CONFIG"

# helper: persist config to file
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
    echo "[$(date '+%F %T')] Config saved." >> "$LOGFILE"
}

# helper: restart systemd objects
reload_systemd() {
    systemctl daemon-reload
    systemctl restart auto-backup.timer 2>/dev/null || true
    systemctl restart auto-backup.service 2>/dev/null || true
    echo "[$(date '+%F %T')] Systemd reloaded & services restarted." >> "$LOGFILE"
}

# UI helpers
pause() {
    read -p "Tekan ENTER untuk lanjut..."
}

confirm() {
    # confirm "Message"
    local msg="$1"
    read -p "$msg (y/N): " ans
    case "$ans" in
        y|Y) return 0 ;;
        *) return 1 ;;
    esac
}

# ---------------------------
# Folder management (existing)
# ---------------------------
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

# ---------------------------
# MySQL advanced editor
# ---------------------------
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
    # parse old
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

# ---------------------------
# PostgreSQL editor & test
# ---------------------------
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

# ---------------------------
# Restore backup
# ---------------------------
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
    # extract (safe mode: extract to temp then copy)
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

# ---------------------------
# Recreate / Repair installer (rebuild service/timer/runner from config)
# ---------------------------
rebuild_installer_files() {
    echo "Membangun ulang service, timer, dan backup-runner berdasarkan config..."
    # rebuild backup-runner if missing
    cat <<'EOR' > "$RUNNER"
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

# backup folders
IFS=',' read -r -a FOLDERS <<< "$FOLDERS_RAW"
for f in "${FOLDERS[@]}"; do
    if [ -d "$f" ]; then
        cp -a "$f" "$TMP_DIR/"
    fi
done

# backup mysql
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

# backup postgres
if [[ "$USE_PG" == "y" ]]; then
    mkdir -p "$TMP_DIR/postgres"
    su - postgres -c "pg_dumpall > $TMP_DIR/postgres/all.sql"
fi

tar -czf "$FILE" -C "$TMP_DIR" .
curl -s -F document=@"$FILE" -F caption="Backup selesai: $(basename $FILE)" "https://api.telegram.org/bot$BOT_TOKEN/sendDocument?chat_id=$CHAT_ID"
rm -rf "$TMP_DIR"
find "$BACKUP_DIR" -type f -mtime +$RETENTION_DAYS -delete
EOR
    chmod +x "$RUNNER"
    echo "[OK] Backup runner dibuat/diupdate: $RUNNER"

    # rebuild service
    cat <<EOT > "$SERVICE_FILE"
[Unit]
Description=Auto Backup VPS to Telegram
After=network.target mysql.service mariadb.service postgresql.service

[Service]
Type=oneshot
Environment="TZ=$TZ"
ExecStart=/usr/bin/env TZ=$TZ $RUNNER
User=root

[Install]
WantedBy=multi-user.target
EOT

    # rebuild timer (try to preserve OnCalendar from existing if any)
    CURRENT_ONCAL="*-*-* 03:00:00"
    if [[ -f "$TIMER_FILE" ]]; then
        # try to extract OnCalendar line
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

    systemctl daemon-reload
    systemctl enable --now auto-backup.timer
    systemctl enable auto-backup.service
    echo "[OK] Service & timer dibuat / direpair."
    echo "[$(date '+%F %T')] Rebuilt installer files." >> "$LOGFILE"
}

# ---------------------------
# Backup encryption (zip + password)
# ---------------------------
encrypt_last_backup() {
    mkdir -p "$INSTALL_DIR/backups"
    LAST=$(ls -1t "$INSTALL_DIR/backups" 2>/dev/null | head -n1)
    if [[ -z "$LAST" ]]; then echo "Tidak ada backup untuk diencrypt."; return; fi
    read -s -p "Masukkan password enkripsi (akan digunakan untuk zip): " PWD; echo ""
    OUT="$INSTALL_DIR/backups/${LAST%.*}.zip"
    # zip with password (zip -P)
    if command -v zip >/dev/null 2>&1; then
        zip -P "$PWD" "$OUT" "$INSTALL_DIR/backups/$LAST" >/dev/null 2>&1
        echo "Encrypted archive dibuat: $OUT"
    else
        echo "Perintah zip tidak tersedia. Install zip lalu ulangi."
    fi
}

# ---------------------------
# OnCalendar helper (interactive)
# ---------------------------
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

# ---------------------------
# Show config & quick actions
# ---------------------------
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

# ---------------------------
# Main menu
# ---------------------------
while true; do
    clear
    echo "=============================================="
    echo "   AUTO BACKUP — MENU PRO (Telegram VPS)"
    echo "=============================================="
    echo "1) Lihat konfigurasi"
    echo "2) Edit BOT TOKEN"
    echo "3) Edit CHAT ID"
    echo "4) Tambah folder backup"
    echo "5) Hapus folder backup"
    echo "6) Tambah konfigurasi MySQL"
    echo "7) Edit konfigurasi MySQL"
    echo "8) Hapus konfigurasi MySQL"
    echo "9) Edit PostgreSQL settings & test dump"
    echo "10) Ubah timezone"
    echo "11) Ubah retention days"
    echo "12) Ubah jadwal backup (OnCalendar helper)"
    echo "13) Test backup sekarang"
    echo "14) Restore dari backup"
    echo "15) Rebuild / Repair installer files (service/timer/runner)"
    echo "16) Encrypt latest backup (zip with password)"
    echo "17) Restart service & timer"
    echo "18) Simpan config"
    echo "0) Keluar (tanpa simpan)"
    echo "----------------------------------------------"
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
        9) edit_pg; pause ;;
        10) read -p "Masukkan timezone (ex: Asia/Jakarta): " NEWTZ; TZ="$NEWTZ"; timedatectl set-timezone "$TZ"; echo "[OK] TZ set to $TZ"; pause ;;
        11) read -p "Masukkan retention days: " RETENTION_DAYS; echo "[OK] Retention set to $RETENTION_DAYS"; pause ;;
        12) build_oncalendar; pause ;;
        13) test_backup; pause ;;
        14) restore_backup; pause ;;
        15) if confirm "Anda yakin ingin (re)build installer files?"; then rebuild_installer_files; fi; pause ;;
        16) encrypt_last_backup; pause ;;
        17) reload_systemd; pause ;;
        18) save_config; pause ;;
        0) echo "Keluar tanpa menyimpan." ; break ;;
        *) echo "Pilihan tidak valid." ; sleep 1 ;;
    esac
done

exit 0
