#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR=${INSTALL_DIR:-/opt/picontrol}
SERVICE_USER=${SERVICE_USER:-pi}
SERVICE_PORT=${SERVICE_PORT:-8129}
REPO_URL=${REPO_URL:-""}

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run as root (sudo ./setup.sh)"
  exit 1
fi

read -rp "API token for service (leave blank for none): " API_TOKEN
read -rp "Apply permissions for /boot/firmware/fullpageos.txt? (y/N): " APPLY_PERMS

if [ ! -f "./requirements.txt" ]; then
  if [ -z "$REPO_URL" ]; then
    echo "requirements.txt not found. Run from repo root or set REPO_URL to clone."
    exit 1
  fi
  TMP_DIR=$(mktemp -d)
  git clone "$REPO_URL" "$TMP_DIR"
  SRC_DIR="$TMP_DIR"
else
  SRC_DIR="$(pwd)"
fi

mkdir -p "$INSTALL_DIR"
rsync -a --exclude '.venv' --exclude '__pycache__' "$SRC_DIR/" "$INSTALL_DIR/"

python3 -m venv "$INSTALL_DIR/.venv"
"$INSTALL_DIR/.venv/bin/pip" install -r "$INSTALL_DIR/requirements.txt"

CONFIG_FILE="$INSTALL_DIR/config.yaml"
if [ ! -f "$CONFIG_FILE" ]; then
  cp "$INSTALL_DIR/config.example.yaml" "$CONFIG_FILE"
fi

if [ -n "$API_TOKEN" ]; then
  sed -i "s/^api_token:.*/api_token: \"$API_TOKEN\"/" "$CONFIG_FILE"
fi

sed -i "s|^fullpageos_path:.*|fullpageos_path: \"/boot/firmware/fullpageos.txt\"|" "$CONFIG_FILE"

mkdir -p /etc/systemd/system
SERVICE_FILE="/etc/systemd/system/picontrol.service"
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Pi Control Service
After=network.target

[Service]
Type=simple
User=$SERVICE_USER
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/.venv/bin/uvicorn app:app --host 0.0.0.0 --port $SERVICE_PORT
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now picontrol.service

if [[ "${APPLY_PERMS,,}" == "y" || "${APPLY_PERMS,,}" == "yes" ]]; then
  groupadd -f picontrol
  usermod -a -G picontrol "$SERVICE_USER"
  chgrp picontrol /boot/firmware/fullpageos.txt
  chmod 664 /boot/firmware/fullpageos.txt
  echo "Updated permissions for /boot/firmware/fullpageos.txt."
fi

echo "Installed and started Pi Control service on port $SERVICE_PORT."
