#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR=${INSTALL_DIR:-/opt/picontrol}
DEFAULT_USER=${SUDO_USER:-""}
if [ -z "$DEFAULT_USER" ]; then
  DEFAULT_USER="$(id -un)"
fi
SERVICE_USER=${SERVICE_USER:-"$DEFAULT_USER"}
SERVICE_PORT=${SERVICE_PORT:-8129}
REPO_URL=${REPO_URL:-"https://github.com/weegeeday/HA-RpiControl-PI.git"}

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run as root (sudo ./setup.sh)"
  exit 1
fi

read -rp "API token for service (leave blank for none): " API_TOKEN
read -rp "Apply permissions for /boot/firmware/fullpageos.txt? (y/N): " APPLY_PERMS

for cmd in git rsync python3; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd"
    exit 1
  fi
done

if ! python3 -m venv /tmp/picontrol-venv-check >/dev/null 2>&1; then
  echo "python3-venv is required. Install with: sudo apt-get install -y python3-venv cec-utils"
  exit 1
fi
rm -rf /tmp/picontrol-venv-check

if ! command -v cec-client >/dev/null 2>&1; then
  echo "cec-utils is required for HDMI CEC control. Install with: sudo apt-get install -y cec-utils"
  # Don't fail the setup if only cec-utils is missing, just let the user know.
fi

if ! id -u "$SERVICE_USER" >/dev/null 2>&1; then
  echo "Service user '$SERVICE_USER' does not exist."
  exit 1
fi

if [ -f "./requirements.txt" ]; then
  SRC_DIR="$(pwd)"
elif [ -f "./PI/requirements.txt" ]; then
  SRC_DIR="$(pwd)/PI"
else
  TMP_DIR=$(mktemp -d)
  git clone "$REPO_URL" "$TMP_DIR"
  REQ_PATH=$(find "$TMP_DIR" -maxdepth 4 -name requirements.txt -print -quit)
  if [ -z "$REQ_PATH" ]; then
    echo "requirements.txt not found in cloned repo."
    exit 1
  fi
  SRC_DIR="$(dirname "$REQ_PATH")"
fi

mkdir -p "$INSTALL_DIR"
rsync -a --exclude '.venv' --exclude '__pycache__' "$SRC_DIR/" "$INSTALL_DIR/"

if [ ! -f "$INSTALL_DIR/requirements.txt" ]; then
  echo "requirements.txt missing after sync; aborting."
  exit 1
fi

chown -R "$SERVICE_USER":"$SERVICE_USER" "$INSTALL_DIR"
chmod -R u+rwX,go+rX "$INSTALL_DIR"

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
  if id -u "$SERVICE_USER" >/dev/null 2>&1; then
    usermod -a -G picontrol "$SERVICE_USER"
  fi
  chgrp picontrol /boot/firmware/fullpageos.txt
  chmod 664 /boot/firmware/fullpageos.txt
  echo "Updated permissions for /boot/firmware/fullpageos.txt."
fi

echo "Installed and started Pi Control service on port $SERVICE_PORT."
