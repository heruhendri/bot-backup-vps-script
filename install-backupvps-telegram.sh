#!/bin/bash

# ==========================================
#  AUTO BACKUP BOT MENU SYSTEM
#  FULL COLOR + ANIMATED BANNER
#  BY HENDRI
# ==========================================

# Warna
CYAN="\e[96m"
BLUE="\e[38;5;51m"
WHITE="\e[1;97m"
GRAY="\e[90m"
NC="\e[0m"

# ============= BANNER ANIMASI ===============
type_animate () {
    text="$1"
    delay="0.002"
    for (( i=0; i<${#text}; i++ )); do
        echo -ne "${text:$i:1}"
        sleep $delay
    done
    echo ""
}

show_banner() {
    clear
    echo -e "${BLUE}"
    type_animate "██████╗  █████╗ ██╗  ██╗██╗   ██╗███████╗"
    type_animate "██╔══██╗██╔══██╗██║ ██╔╝██║   ██║██╔════╝"
    type_animate "██████╔╝███████║█████╔╝ ██║   ██║█████╗  "
    type_animate "██╔══██╗██╔══██║██╔═██╗ ██║   ██║██╔══╝  "
    type_animate "██████╔╝██║  ██║██║  ██╗╚██████╔╝███████╗"
    type_animate "╚═════╝ ╚═╝  ██║╚═╝  ╚═╝ ╚═════╝ ╚══════╝"
    echo -e "${NC}"

    echo -e "${WHITE}===============[ AUTO BACKUP BOT SYSTEM ]===============${NC}"
    echo -e "${CYAN}===================== BY HENDRI =========================${NC}"
    echo ""
}

# ===================== STATUS ======================
show_status() {
    clear
    show_banner

    echo -e "${WHITE}[ STATUS BACKUP BOT ]${NC}"
    echo ""
    systemctl is-active auto-backup >/dev/null 2>&1 && STATUS="ACTIVE" || STATUS="INACTIVE"
    
    echo -e "Service Status  : ${CYAN}$STATUS${NC}"
    echo -e "Last Backup     : ${CYAN}$(grep 'BACKUP FINISHED' /var/log/auto-backup.log | tail -n 1)${NC}"
    echo -e "Next Scheduled  : ${CYAN}$(systemctl list-timers | grep auto-backup | awk '{print $5, $6}')${NC}"
    echo ""
    
    echo -e "${GRAY}=========================================================${NC}"
    echo -e "${GRAY}Support: BY HENDRI — whatsapp.com/send?phone=62xxxxxxxx${NC}"
    echo -e "${GRAY}=========================================================${NC}"
    echo ""
    read -p "Tekan ENTER untuk kembali..."
}

# ===================== MANAGE FOLDERS ======================
manage_folders() {
    clear
    show_banner

    echo -e "${WHITE}[ MANAGE FOLDER BACKUP ]${NC}"
    echo ""
    echo -e "1) Tambah Folder"
    echo -e "2) Hapus Folder"
    echo -e "3) Lihat Daftar Folder"
    echo -e "0) Kembali"
    echo ""

    read -p "Pilih menu: " pil

    case $pil in
        1)
            read -p "Masukkan folder path: " fold
            echo "$fold" >> /opt/auto-backup/folders.conf
            echo "Folder ditambahkan!"
            sleep 1
        ;;
        2)
            nano /opt/auto-backup/folders.conf
        ;;
        3)
            cat /opt/auto-backup/folders.conf
            read -p "ENTER untuk kembali"
        ;;
    esac

    manage_folders
}

# ===================== MYSQL MENU ======================
menu_mysql() {
    clear
    show_banner

    echo -e "${WHITE}[ MYSQL DATABASE BACKUP ]${NC}"
    echo ""
    echo "1) Tambah Database"
    echo "2) Edit Database"
    echo "3) Lihat Daftar"
    echo "0) Kembali"
    echo ""
    read -p "Pilih menu: " dbs

    case $dbs in
        1)
            read -p "Nama DB: " name
            read -p "User: " user
            read -p "Pass: " pass
            echo "$name|$user|$pass" >> /opt/auto-backup/mysql.conf
            echo "Database ditambahkan!"
            sleep 1
        ;;
        2)
            nano /opt/auto-backup/mysql.conf
        ;;
        3)
            cat /opt/auto-backup/mysql.conf
            read -p "ENTER untuk kembali"
        ;;
    esac

    menu_mysql
}

# ===================== LOG SYSTEM ======================
menu_logs() {
    clear
    show_banner
    
    echo -e "${WHITE}[ LOG BACKUP ]${NC}"
    echo ""
    tail -n 50 /var/log/auto-backup.log
    echo ""
    read -p "ENTER untuk kembali"
}

# ===================== MENU UTAMA ======================
main_menu() {
    while true; do
        clear
        show_banner
        
        echo -e "${WHITE}[ MAIN MENU ]${NC}"
        echo ""
        echo -e "1) Status Backup"
        echo -e "2) Manage Folder Backup"
        echo -e "3) Manage MySQL"
        echo -e "4) Logs"
        echo -e "0) Exit"
        echo ""
        echo -e "${GRAY}=========================================================${NC}"
        echo -e "${GRAY}Watermark: BY HENDRI — Professional Backup Service${NC}"
        echo -e "${GRAY}=========================================================${NC}"
        echo ""

        read -p "Pilih menu: " menu

        case $menu in
            1) show_status ;;
            2) manage_folders ;;
            3) menu_mysql ;;
            4) menu_logs ;;
            0) exit 0 ;;
            *) echo "Pilihan tidak valid"; sleep 1 ;;
        esac
    done
}

main_menu
