#!/bin/bash
set -euo pipefail

# PRO Menu for Auto Backup VPS — TELEGRAM BOT (v22)
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
    mkdir -p "$(dirname "$LOGFILE")"
    touch "$LOGFILE"
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

# ---------- Status (static) ----------
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

    next_run=$(systemctl list-timers --all 2>/dev/null | grep auto-backup.timer | awk '{print $1, $2, $3}' | head -n1)
    [[ -z "$next_run" ]] && next_run="(tidak tersedia)"
    echo "Next run       : $next_run"

    BACKUP_DIR="$INSTALL_DIR/backups"
    lastfile=$(ls -1t "$BACKUP_DIR" 2>/dev/null | head -n1 || true)
    if [[ -n "$lastfile" ]]; then
        lasttime=$(stat -c '%y' "$BACKUP_DIR/$lastfile" | cut -d'.' -f1)
        echo "Last backup    : $lastfile ($lasttime)"
    else
        echo "Last backup    : (belum ada)"
    fi

    echo ""
    echo "--- Log (5 baris terakhir) ---"
    journalctl -u auto-backup.service -n 5 --no-pager || echo "(log tidak tersedia)"

    echo ""
    pause
}

# -------- Show Status Live (fixed auto-refresh) ----------
show_status_live() {
    # ensure terminal cleanup on exit
    trap 'tput cnorm; stty sane; clear; echo "Keluar dari mode realtime."; exit 0' SIGINT SIGTERM

    # hide cursor
    tput civis 2>/dev/null || true

    while true; do
        clear
        echo -e "\e[36m$WATERMARK_HEADER\e[0m"
        echo "        STATUS BACKUP — REALTIME (Refresh 1 detik)"
        echo ""

        GREEN="\e[32m"
        BLUE="\e[34m"
        RESET="\e[0m"

        # Service status
        svc_active=$(systemctl is-active auto-backup.service 2>/dev/null || echo "unknown")
        svc_enabled=$(systemctl is-enabled auto-backup.service 2>/dev/null || echo "unknown")
        echo "Service status : $svc_active (enabled: $svc_enabled)"

        # Timer status
        tm_active=$(systemctl is-active auto-backup.timer 2>/dev/null || echo "unknown")
        tm_enabled=$(systemctl is-enabled auto-backup.timer 2>/dev/null || echo "unknown")
        echo "Timer status   : $tm_active (enabled: $tm_enabled)"

        # Next run (safe parse)
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

        # Time left + progress
        if [[ "$next_run" =~ ^\( ]]; then
            echo "Time left      : (tidak tersedia)"
            echo "Progress       : (tidak tersedia)"
        else
            # prevent date -d errors by checking non-empty
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

                # last run epoch (from journal)
                last_epoch=$(journalctl -u auto-backup.service --output=short-unix -n 50 --no-pager \
                    | awk '/Backup done/ {print $1; exit}' | cut -d'.' -f1 || true)

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

        # Last backup file
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
        # sleep 1 with interruptability
        sleep 1 || true
    done

    # restore cursor on exit (in case trap didn't run)
    tput cnorm 2>/dev/null || true
}

# ---------- Folder / MySQL / PG functions ----------
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

if [[ "$USE_PG" == "y" ]]; then
    mkdir -p "$TMP_DIR/postgres"
    su - postgres -c "pg_dumpall > $TMP_DIR/postgres/all.sql" || true
fi

tar -czf "$FILE" -C "$TMP_DIR" . || true
curl -s -F document=@"$FILE" -F caption="Backup selesai: $(basename $FILE)" "https://api.telegram.org/bot$BOT_TOKEN/sendDocument?chat_id=$CHAT_ID" || true
rm -rf "$TMP_DIR"
find "$BACKUP_DIR" -type f -mtime +$RETENTION_DAYS -delete || true
EOR
    chmod +x "$RUNNER"
    echo "[OK] Backup runner dibuat/diupdate: $RUNNER"

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

# Main menu
while true; do
    clear
    echo "$WATERMARK_HEADER"
    echo ""
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
    echo "19) Status (service / last backup / next run)"
    echo "20) Status Realtime (live monitor)"
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
        19) show_status ;;
        20) show_status_live ;;
        0) echo "Keluar tanpa menyimpan." ; break ;;
        *) echo "Pilihan tidak valid." ; sleep 1 ;;
    esac
done

exit 0
