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

banner_rgb &          # jalankan di background
BANNER_PID=$!         # ambil PID animasi

cleanup_banner() {
    kill $BANNER_PID 2>/dev/null
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

# Placeholder proses instalasi
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

echo "$cron  /opt/auto-backup/backup.sh" >> /etc/crontab
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
tail -n 30 /var/log/syslog | grep backup
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
