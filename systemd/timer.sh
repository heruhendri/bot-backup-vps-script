#!/bin/bash
set -euo pipefail

BASE_DIR="/opt/auto-backup"
TIMER_FILE="/etc/systemd/system/auto-backup.timer"

CRON_TIME="${1:-}"

if [[ -z "$CRON_TIME" ]]; then
    echo "[ERROR] Tidak ada jadwal OnCalendar diberikan."
    echo "Usage: timer.sh \"*-*-* 03:00:00\""
    exit 1
fi

echo "[INFO] Membuat systemd timer..."

cat > "$TIMER_FILE" <<EOF
[Unit]
Description=Auto Backup VPS Timer

[Timer]
OnCalendar=$CRON_TIME
Persistent=true
Unit=auto-backup.service

[Install]
WantedBy=timers.target
EOF

chmod 644 "$TIMER_FILE"

systemctl daemon-reload
systemctl enable --now auto-backup.timer || true

echo "[OK] Timer dibuat: $TIMER_FILE"
echo "[OK] Jadwal: $CRON_TIME"
