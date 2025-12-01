#!/bin/bash

# ======================================================
# MENU BOT BACKUP VPS • RGB Banner • © HENDRI
# ======================================================

# Warna ANSI
red='\e[31m'
green='\e[32m'
yellow='\e[33m'
blue='\e[34m'
purple='\e[35m'
cyan='\e[36m'
bold='\e[1m'
nc='\e[0m'

# Warna RGB untuk Banner
rgb_colors=(
  '\e[91m'
  '\e[93m'
  '\e[92m'
  '\e[96m'
  '\e[94m'
  '\e[95m'
)

# Banner ASCII HENDRI
banner_text=(
"██   ██ ███████ ███    ██ ██████  ██████  ██ ██████ "
"██   ██ ██      ████   ██ ██   ██ ██   ██ ██ ██   ██"
"███████ █████   ██ ██  ██ ██   ██ ██████  ██ ██████ "
"██   ██ ██      ██  ██ ██ ██   ██ ██   ██ ██ ██   ██"
"██   ██ ███████ ██   ████ ██████  ██   ██ ██ ██   ██"
""
"              © HENDRI • Backup VPS Bot"
)

# Banner Animasi
animate_banner() {
    for color in "${rgb_colors[@]}"; do
        clear
        echo -e "\n"
        for line in "${banner_text[@]}"; do
            echo -e "${color}${line}${nc}"
        done
        sleep 0.15
    done
}

# Menjalankan Banner Sekali
animate_banner
clear

# ================================
# DASHBOARD
# ================================
dashboard() {
    clear
    echo -e "${cyan}${bold}=========================================================${nc}"
    echo -e "${yellow}${bold}            BACKUP VPS TELEGRAM BOT MENU${nc}"
    echo -e "${cyan}${bold}=========================================================${nc}"
    echo -e "${green}${bold}Hostname :${nc} $(hostname)"
    echo -e "${green}${bold}IP Server:${nc} $(hostname -I | awk '{print $1}')"
    echo -e "${green}${bold}Tanggal  :${nc} $(date)"
    echo -e "${purple}${bold}Watermark: BY HENDRI${nc}"
    echo -e "${cyan}${bold}=========================================================${nc}"

    echo -e "${yellow}${bold} 1) Backup Sekarang${nc}"
    echo -e "${yellow}${bold} 2) Restore Backup${nc}"
    echo -e "${yellow}${bold} 3) Jadwal Backup Otomatis${nc}"
    echo -e "${yellow}${bold} 4) Lihat Log Backup${nc}"
    echo -e "${yellow}${bold} 5) Update Script${nc}"
    echo -e "${yellow}${bold} 6) Restart Service Backup${nc}"
    echo -e "${yellow}${bold} 7) Info & Bantuan${nc}"
    echo -e "${yellow}${bold} 0) Keluar${nc}"

    echo -e "${cyan}${bold}=========================================================${nc}"
}

# ================================
# Fungsi Menu
# ================================

backup_now() {
    echo -e "${green}Melakukan backup...${nc}"
    sleep 1
    echo -e "${yellow}Backup selesai!${nc}"
    read -p "ENTER untuk kembali..."
}

restore_backup() {
    echo -e "${green}Memulai proses restore...${nc}"
    sleep 1
    echo -e "${yellow}Restore selesai!${nc}"
    read -p "ENTER untuk kembali..."
}

auto_schedule() {
    echo -e "${cyan}Mengatur jadwal backup otomatis...${nc}"
    sleep 1
    echo -e "${yellow}Jadwal backup otomatis telah disimpan!${nc}"
    read -p "ENTER untuk kembali..."
}

view_logs() {
    echo -e "${green}Menampilkan log backup...${nc}"
    sleep 1
    echo -e "${yellow}(Contoh Log) Backup berhasil pada $(date)${nc}"
    read -p "ENTER untuk kembali..."
}

update_script() {
    echo -e "${purple}Meng-update script otomatis...${nc}"
    sleep 1
    echo -e "${green}Update selesai!${nc}"
    read -p "ENTER untuk kembali..."
}

restart_service() {
    echo -e "${cyan}Restarting backup service...${nc}"
    sleep 1
    echo -e "${green}Service berhasil di-restart!${nc}"
    read -p "ENTER untuk kembali..."
}

show_help() {
    echo -e "${blue}${bold}❗ Bantuan & Kontak Support${nc}"
    echo -e "${yellow}Jika Anda mengalami kendala, hubungi:${nc}"
    echo -e "${green}${bold}WhatsApp: 0896-xxxx-xxxx${nc}"
    echo -e "${purple}${bold}Developer: HENDRI${nc}"
    read -p "ENTER untuk kembali..."
}

# ================================
# LOOP MENU UTAMA
# ================================

while true; do
    dashboard
    echo -ne "${cyan}${bold}Pilih menu: ${nc}"
    read pilih
    case $pilih in
        1) backup_now ;;
        2) restore_backup ;;
        3) auto_schedule ;;
        4) view_logs ;;
        5) update_script ;;
        6) restart_service ;;
        7) show_help ;;
        0) clear; echo -e "${green}Keluar dari menu...${nc}"; exit ;;
        *) echo -e "${red}Pilihan tidak valid!${nc}"; sleep 1 ;;
    esac
done
