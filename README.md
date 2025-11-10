# bot-backup-vps-script

Ada 2 langkah besar:

---

## 1. Buat Bot Telegram & Dapatkan Chat ID

1. Buka Telegram, cari **@BotFather**.
2. Buat bot baru dengan perintah:

   ```
   /newbot
   ```

   Ikuti instruksi, nanti kamu dapat **token bot** (contoh: `123456:ABC-DEF...`).
3. Invite bot itu ke grup/channel kamu (kalau mau dikirim ke grup).
4. Cari **chat\_id** dengan kirim pesan ke bot lalu buka:

   ```
   https://api.telegram.org/botTOKEN/getUpdates
   ```

   (ganti `TOKEN` dengan token bot tadi).
   Nanti akan muncul JSON, di dalamnya ada `"chat":{"id": ... }` → itu chat\_id.

---

## 2. Script Backup & Kirim ke Telegram

Misalnya kamu ingin backup file `/root/backup/kuma.tar.gz` lalu kirim otomatis.

Buat file script `backup.sh`:

```bash
#!/bin/bash

# === Konfigurasi ===
BOT_TOKEN="8376772650:AAFKk6dpGu91zUJJetNzN0helZihdob_4oc"   # ganti dengan token bot kamu
CHAT_ID="8264681468"             # ganti dengan chat_id kamu
BACKUP_DIR="/root/backup"
FILE_NAME="backup-$(date +%F-%H%M).tar.gz"
TARGET="$BACKUP_DIR/$FILE_NAME"

# === Buat backup (contoh: backup folder /app/data) ===
mkdir -p $BACKUP_DIR
tar -czf $TARGET /var/lib/docker/volumes/uptime-kuma/

# === Kirim ke Telegram ===
curl -F document=@"$TARGET" \
     -F caption="Backup berhasil: $FILE_NAME" \
     "https://api.telegram.org/bot$BOT_TOKEN/sendDocument?chat_id=$CHAT_ID"
```

---

## 3. Jadwalkan dengan Cron

Agar otomatis jalan tiap hari (misal jam 01:00 pagi):

```bash
crontab -e
```

Tambahkan baris:

```
0 1 * * * /bin/bash /root/backup.sh
```

---

## 4. Hasil

* Setiap jam 01:00, VPS akan membuat file backup.
* File backup otomatis dikirim ke bot Telegram.
* Kamu bisa cek log di Telegram langsung.

---

## Jika Terjadi Eror
root@server:~# crontab -e
no crontab for root - using an empty one

Select an editor.  To change later, run 'select-editor'.
  1. /bin/nano        <---- easiest
  2. /usr/bin/vim.basic
  3. /bin/ed

Choose 1-3 [1]: 



👉 Saran: ketik **1** (nano, paling gampang).

Jadi langkahnya:

1. Ketik:

   ```
   1
   ```

   lalu Enter.

2. Setelah itu, file crontab kosong akan terbuka di editor `nano`.

3. Tambahkan jadwal cron kamu, misalnya (backup setiap jam 01:00):

   ```
   0 1 * * * /bin/bash /root/backup.sh
   ```

4. Simpan di nano:

   * Tekan **CTRL+O** (untuk save), lalu Enter.
   * Tekan **CTRL+X** (untuk keluar).

5. Pastikan script `backup.sh` kamu sudah diberi izin eksekusi:

   ```bash
   chmod +x /root/backup.sh
   ```

6. Cron akan otomatis menjalankan script sesuai jadwal.

---

## Cara Testnya

Mantap, kalau mau **test langsung** tanpa tunggu cron jalan, kamu bisa eksekusi script manual:

1. Pastikan script sudah executable:

   ```bash
   chmod +x /root/backup.sh
   ```

2. Jalankan langsung:

   ```bash
   /root/backup.sh
   ```

3. Kalau script benar, dia akan:

   * Membuat file backup (contoh: `/root/backup/backup-2025-08-19-1430.tar.gz`).
   * Mengirim file tersebut ke bot Telegram kamu.

---

🔍 Kalau mau lihat detail error (kalau ada), jalankan dengan `bash -x`:

```bash
bash -x /root/backup.sh
```

---

👉 Kalau mau test cron juga, kamu bisa set jadwal per menit supaya cepat terlihat hasilnya. Edit crontab:

```bash
* * * * * /bin/bash /root/backup.sh
```

Itu artinya script dijalankan **setiap menit**.
Kalau sudah yakin jalan, ganti lagi ke `0 1 * * *` (jam 1 pagi).

---

## Seting Jam DI Ubuntu


### 1. Cek Waktu Saat Ini

Jalankan:

```bash
timedatectl
```

Hasilnya akan menunjukkan:

* Local time (jam lokal)
* Time zone (zona waktu)
* NTP service aktif atau tidak

---

### 2. Atur Zona Waktu

Misalnya untuk **WIB (Asia/Jakarta)**:

```bash
sudo timedatectl set-timezone Asia/Jakarta
```

Cek lagi:

```bash
timedatectl
```

---

### 3. Sinkronisasi dengan NTP

Agar jam otomatis benar:

```bash
sudo timedatectl set-ntp true
```

Ini akan mengaktifkan sinkronisasi dengan server waktu internet.

---

### 4. Atur Jam Manual (Jika Perlu)

Kalau VPS tidak bisa NTP atau butuh jam manual:

```bash
sudo timedatectl set-time "2025-09-29 19:30:00"
```

---

### 5. Simpan ke Hardware Clock

Agar reboot tidak mengubah jam:

```bash
sudo hwclock --systohc
```

---

