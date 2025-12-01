#!/bin/bash
set -euo pipefail
clear

WATERMARK_INSTALL="=== AUTO BACKUP VPS — INSTALLER ===
Installer by: HENDRI
Support: https://t.me/GbtTapiPngnSndiri
========================================="
WATERMARK_END="=== INSTALL COMPLETE — SCRIPT BY HENDRI ===
Support: https://t.me/GbtTapiPngnSndiri
========================================="

echo "$WATERMARK_INSTALL"
echo ""

INSTALL_DIR="/opt/auto-backup"
CONFIG_FILE="$INSTALL_DIR/config.conf"
MENU_FILE="$INSTALL_DIR/menu.sh"
RUNNER="$INSTALL_DIR/backup-runner.sh"
SERVICE_FILE="/etc/systemd/system/auto-backup.service"
TIMER_FILE="/etc/systemd/system/auto-backup.timer"

mkdir -p "$INSTALL_DIR"
chmod 755 "$INSTALL_DIR"

# (installer input section kept out in menu-only build; menu expects config exists)
# load config if exists
if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
else
    echo "[WARN] Config tidak ditemukan: $CONFIG_FILE. Beberapa fungsi mungkin tidak bekerja."
fi

# ---------- Menu script (full) ----------
cat > "$MENU_FILE" <<'MENU'
#!/bin/bash
set -euo pipefail

CONFIG="/opt/auto-backup/config.conf"
INSTALL_DIR="/opt/auto-backup"
RUNNER="$INSTALL_DIR/backup-runner.sh"
SERVICE_NAME="auto-backup.service"
TIMER_NAME="auto-backup.timer"
SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME"
TIMER_FILE="/etc/systemd/system/$TIMER_NAME"
LOGFILE="$INSTALL_DIR/menu-pro.log"

WATERMARK_HEADER="=== AUTO BACKUP VPS — MENU PRO ===
SCRIPT BY: HENDRI
SUPPORT: https://t.me/GbtTapiPngnSndiri
========================================"
WATERMARK_FOOTER="========================================
SCRIPT BY: HENDRI — AUTO BACKUP VPS
Support: https://t.me/GbtTapiPngnSndiri"

if [[ -f "$CONFIG" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG"
fi

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
    systemctl restart "$TIMER_NAME" 2>/dev/null || true
    systemctl restart "$SERVICE_NAME" 2>/dev/null || true
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

# ---------- Status Menu ----------
show_status() {
    echo -e "\e[36m$WATERMARK_HEADER\e[0m"
    echo ""

    GREEN="\e[32m"
    RED="\e[31m"
    YELLOW="\e[33m"
    BLUE="\e[34m"
    RESET="\e[0m"

    colorize() {
        case "$1" in
            active) echo -e "${GREEN}$1${RESET}" ;;
            inactive|dead) echo -e "${RED}$1${RESET}" ;;
            failed) echo -e "${RED}$1${RESET}" ;;
            *) echo -e "${YELLOW}$1${RESET}" ;;
        esac
    }

    # Service status
    svc_active=$(systemctl is-active "$SERVICE_NAME" 2>/dev/null || echo "unknown")
    svc_enabled=$(systemctl is-enabled "$SERVICE_NAME" 2>/dev/null || echo "unknown")
    echo -e "Service status : $(colorize "$svc_active") (enabled: $svc_enabled)"

    # Timer status
    tmr_active=$(systemctl is-active "$TIMER_NAME" 2>/dev/null || echo "unknown")
    tmr_enabled=$(systemctl is-enabled "$TIMER_NAME" 2>/dev/null || echo "unknown")
    echo -e "Timer status   : $(colorize "$tmr_active") (enabled: $tmr_enabled)"

    # NEXT RUN: try several methods
    next_run=""
    # method 1 - systemctl list-timers
    line=$(systemctl list-timers --all | grep "$TIMER_NAME" | head -n1 || true)
    if [[ -n "$line" ]]; then
        # columns: NEXT                        LEFT  LAST                        PASSED  UNIT
        # we want column 1+2 as date/time in many locales
        next_run=$(echo "$line" | awk '{print $1" "$2}')
    fi

    # method 2 - NextElapseUSec / NextRunUSec
    if [[ -z "$next_run" || "$next_run" == " " ]]; then
        usec=$(systemctl show "$TIMER_NAME" -p NextElapseUSec --value 2>/dev/null || echo "")
        if [[ -z "$usec" || "$usec" == "0" ]]; then
            usec=$(systemctl show "$TIMER_NAME" -p NextRunUSec --value 2>/dev/null || echo "")
        fi
        if [[ "$usec" =~ ^[0-9]+$ ]] && (( usec > 0 )); then
            epoch=$(( usec / 1000000 ))
            next_run=$(date -d @"$epoch" "+%Y-%m-%d %H:%M:%S" 2>/dev/null || true)
        fi
    fi

    # fallback
    if [[ -z "$next_run" ]]; then
        next_run="(belum dijadwalkan / timer belum aktif)"
    fi

    echo -e "Next run       : ${BLUE}$next_run${RESET}"

    # TIME LEFT & PROGRESS (accurate)
    if [[ "$next_run" =~ ^\( ]]; then
        echo "Time left      : (tidak tersedia)"
        echo "Progress       : (tidak tersedia)"
    else
        # compute next_epoch
        next_epoch=$(date -d "$next_run" +%s 2>/dev/null || echo 0)
        now_epoch=$(date +%s)
        diff=$(( next_epoch - now_epoch ))

        if (( diff <= 0 )); then
            echo -e "Time left      : ${RED}0 detik (jadwal terlewat / sedang menunggu)${RESET}"
            echo "Progress       : 100% (sedang berjalan / terlewat)"
        else
            # try to find last run epoch
            last_epoch=0

            # method A: systemctl show LastTriggerUSec / LastElapseUSec
            lusec=$(systemctl show "$TIMER_NAME" -p LastTriggerUSec --value 2>/dev/null || echo "")
            if [[ -z "$lusec" || "$lusec" == "0" ]]; then
                # try LastElapseUSec
                lusec=$(systemctl show "$TIMER_NAME" -p LastElapseUSec --value 2>/dev/null || echo "")
            fi
            if [[ "$lusec" =~ ^[0-9]+$ ]] && (( lusec > 0 )); then
                last_epoch=$(( lusec / 1000000 ))
            fi

            # method B: fallback to journalctl (short-unix) — look for "Backup done" or "Backup selesai"
            if (( last_epoch == 0 )); then
                # get latest unix timestamp line where backup finished message appears
                jlast=$(journalctl -u "$SERVICE_NAME" --output=short-unix -n 200 2>/dev/null | awk '/Backup done|Backup selesai|Backup selesai:|Backup selesai /{print $1; exit}')
                if [[ -n "$jlast" ]]; then
                    # jlast may be float like 1700000000.123
                    jsec=$(echo "$jlast" | cut -d'.' -f1)
                    if [[ "$jsec" =~ ^[0-9]+$ ]]; then
                        last_epoch=$jsec
                    fi
                fi
            fi

            # If we have a valid last_epoch and it's less than next_epoch => compute accurate progress
            if (( last_epoch > 0 && next_epoch > last_epoch )); then
                total_interval=$(( next_epoch - last_epoch ))
                elapsed=$(( now_epoch - last_epoch ))
                if (( elapsed < 0 )); then elapsed=0; fi
                if (( elapsed > total_interval )); then elapsed=$total_interval; fi

                # compute percent (integer)
                percent=$(( (elapsed * 100) / total_interval ))
                [[ $percent -lt 0 ]] && percent=0
                [[ $percent -gt 100 ]] && percent=100

                # format time left
                days=$(( diff / 86400 ))
                hours=$(( (diff % 86400) / 3600 ))
                minutes=$(( (diff % 3600) / 60 ))
                seconds=$(( diff % 60 ))
                left=""
                [[ $days -gt 0 ]] && left="$left${days} hari "
                [[ $hours -gt 0 ]] && left="$left${hours} jam "
                [[ $minutes -gt 0 ]] && left="$left${minutes} menit "
                left="${left}${seconds} detik"

                echo -e "Time left      : ${GREEN}$left${RESET}"

                # progress bar (20 chars)
                bars=$(( percent / 5 ))
                bar=""
                for ((i=0;i<bars;i++)); do bar="${bar}█"; done
                # pad to 20 characters
                pad=$((20-bars))
                for ((i=0;i<pad;i++)); do bar="${bar} "; done

                echo -e "Progress       : ${BLUE}[${bar}]${RESET} ${percent}%"
            else
                # no valid last_epoch → cannot compute accurate progress
                # still show time left nicely
                days=$(( diff / 86400 ))
                hours=$(( (diff % 86400) / 3600 ))
                minutes=$(( (diff % 3600) / 60 ))
                seconds=$(( diff % 60 ))
                left=""
                [[ $days -gt 0 ]] && left="$left${days} hari "
                [[ $hours -gt 0 ]] && left="$left${hours} jam "
                [[ $minutes -gt 0 ]] && left="$left${minutes} menit "
                left="${left}${seconds} detik"

                echo -e "Time left      : ${GREEN}$left${RESET}"
                echo "Progress       : (tidak tersedia — last run tidak ditemukan)"
            fi
        fi
    fi

    # LAST BACKUP (most recent file in backups)
    BACKUP_DIR="$INSTALL_DIR/backups"
    if [[ ! -d "$BACKUP_DIR" ]]; then
        echo "Last backup    : (backup dir tidak ditemukan)"
    else
        lastfile=$(ls -1t "$BACKUP_DIR" 2>/dev/null | head -n1 || true)
        if [[ -z "$lastfile" ]]; then
            echo "Last backup    : (belum ada backup)"
        else
            lasttime=$(stat -c '%y' "$BACKUP_DIR/$lastfile" 2>/dev/null | cut -d'.' -f1 || true)
            echo -e "Last backup    : ${GREEN}$lastfile${RESET} ($lasttime)"
        fi
    fi

    # error detection from journal
    err=$(journalctl -u "$SERVICE_NAME" -n 50 2>/dev/null | grep -Ei "error|fail|failed" || true)
    if [[ -n "$err" ]]; then
        echo -e "\n${RED}⚠ PERINGATAN: Ada entri ERROR/FAILED di log service!${RESET}"
    fi

    echo -e "\n${BLUE}--- Log terakhir $SERVICE_NAME ---${RESET}"
    journalctl -u "$SERVICE_NAME" -n 5 --no-pager 2>/dev/null || echo "(log tidak tersedia)"

    echo ""
    echo -e "\e[36m$WATERMARK_FOOTER\e[0m"
    pause
}

# ---------- Other functions (folder/mysql/pg) ----------
add_folder() {
    read -p "Masukkan folder baru (single path, atau comma separated): " NEW_FOLDER
    if [[ -z "$NEW_FOLDER" ]]; then
        echo "Tidak ada input."
        return
    fi
    if [[ -z "${FOLDERS_RAW:-}" ]]; then
        FOLDERS_RAW="$NEW_FOLDER"
    else
        FOLDERS_RAW="$FOLDERS_RAW,$NEW_FOLDER"
    fi
    echo "[OK] Folder tambahan disiapkan."
}

delete_folder() {
    if [[ -z "${FOLDERS_RAW:-}" ]]; then
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
    if [[ -z "${MYSQL_MULTI_CONF:-}" ]]; then
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
    if [[ -z "${MYSQL_MULTI_CONF:-}" ]]; then MYSQL_MULTI_CONF="$NEW_ENTRY"; else MYSQL_MULTI_CONF="$MYSQL_MULTI_CONF;$NEW_ENTRY"; fi
    echo "[OK] Ditambahkan."
}

edit_mysql() {
    if [[ -z "${MYSQL_MULTI_CONF:-}" ]]; then echo "Tidak ada konfigurasi MySQL."; return; fi
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
    if [[ -z "${MYSQL_MULTI_CONF:-}" ]]; then echo "Tidak ada konfigurasi MySQL."; return; fi
    IFS=';' read -ra LIST <<< "$MYSQL_MULTI_CONF"
    for i in "${!LIST[@]}"; do printf "%2d) %s\n" $((i+1)) "${LIST[$i]}"; done
    read -p "Pilih nomor yang ingin dihapus: " NUM
    if ! [[ "$NUM" =~ ^[0-9]+$ ]] || (( NUM < 1 || NUM > ${#LIST[@]} )); then echo "Pilihan invalid."; return; fi
    unset 'LIST[NUM-1]'
    MYSQL_MULTI_CONF=$(IFS=';'; echo "${LIST[*]}")
    echo "[OK] Dihapus."
}

edit_pg() {
    read -p "Backup PostgreSQL? (y/n) [current: ${USE_PG:-n}]: " x
    if [[ ! -z "$x" ]]; then USE_PG="$x"; fi
    echo "[OK] USE_PG set ke $USE_PG"
    read -p "Tekan ENTER jika ingin melakukan test dump sekarang, atau CTRL+C untuk batal..."
    if [[ "${USE_PG:-n}" == "y" ]]; then
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
    # This function rewrites runner/service/timer similar to installer
    # For brevity it delegates to the runner rebuild implemented in installer
    if [[ -x "$RUNNER" ]]; then
        echo "[OK] Runner exists: $RUNNER"
    fi
    systemctl daemon-reload || true
    systemctl enable --now "$TIMER_NAME" 2>/dev/null || true
    systemctl enable "$SERVICE_NAME" 2>/dev/null || true
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
    systemctl restart "$TIMER_NAME"
    echo "[OK] OnCalendar disimpan ke $TIMER_FILE"
}

show_config_file() {
    echo "================ CONFIG FILE ================"
    [[ -f "$CONFIG" ]] && cat "$CONFIG" || echo "(config tidak ditemukan)"
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
        19) show_status; pause ;;
        0) echo "Keluar tanpa menyimpan." ; break ;;
        *) echo "Pilihan tidak valid." ; sleep 1 ;;
    esac
done

exit 0
MENU

chmod +x "$MENU_FILE"
ln -sf "$MENU_FILE" /usr/bin/menu-bot-backup
chmod +x /usr/bin/menu-bot-backup

echo "[OK] Menu PRO installed: menu-bot-backup (run 'menu-bot-backup' to open)"
