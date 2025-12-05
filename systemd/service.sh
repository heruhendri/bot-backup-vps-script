#!/bin/bash
set -euo pipefail

BASE_DIR="/opt/auto-backup"
RUNNER="$BASE_DIR/runner/backup-runner.sh"
SERVICE_FILE="/etc/systemd/system/auto-backup.service"
CONFIG_FILE="$BASE_DIR/config.conf"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "[ERROR] config.conf tidak ditemukan!"
    exit 1
fi

# load config
# shellcheck source=/dev/null
source "$CONFIG_FILE"

TZ="${TZ:-UTC}"

echo "[INFO] Membuat systemd service..."

cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Auto Backup VPS to Telegram
After=network.target mysql.service mariadb.service postgresql.service mongodb.service

[Service]
Type=oneshot
Environment="TZ=$TZ"
ExecStart=/usr/bin/env TZ=$TZ $RUNNER
User=root

[Install]
WantedBy=multi-user.target
EOF

chmod 644 "$SERVICE_FILE"

systemctl daemon-reload
systemctl enable auto-backup.service || true

echo "[OK] Service dibuat: $SERVICE_FILE"
