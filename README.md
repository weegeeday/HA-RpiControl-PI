# Pi Control Service

A small HTTP service for Home Assistant to reboot the Pi, read/write `/boot/firmware/fullpageos.txt`, and run SSH commands. The service itself runs as a normal (non-admin) user; you must grant file and reboot permissions separately.

## Setup

1. Copy the service to the Pi, for example `/opt/picontrol`.
2. Create and activate a virtual environment, then install requirements.
3. Copy `config.example.yaml` to `config.yaml` and set `api_token`.

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp config.example.yaml config.yaml
```

## Permissions (required)

### Allow editing `/boot/firmware/fullpageos.txt`

Give the service user group access to the file (example uses group `picontrol`):

```bash
sudo groupadd picontrol
sudo usermod -a -G picontrol pi
sudo chgrp picontrol /boot/firmware/fullpageos.txt
sudo chmod 664 /boot/firmware/fullpageos.txt
```

### Allow reboot without sudo

If you want the reboot endpoint to work, you must allow the service user to reboot without interactive sudo. One option is a polkit rule that grants `reboot` for the service user. This step requires admin setup.

## Run

```bash
.venv/bin/uvicorn app:app --host 0.0.0.0 --port 8129
```

## Simple setup script

Run from the `PI` folder on the Pi:

```bash
chmod +x setup.sh
sudo ./setup.sh
```

If you want to run it from anywhere, pass a repo URL:

```bash
sudo REPO_URL="https://github.com/weegeeday/HA-RpiControl-PI.git" ./setup.sh
```

The script can optionally apply permissions for `/boot/firmware/fullpageos.txt`.

## Systemd unit (optional)

Edit `systemd/picontrol.service` to match your user and path, then enable it:

```bash
sudo cp systemd/picontrol.service /etc/systemd/system/picontrol.service
sudo systemctl daemon-reload
sudo systemctl enable --now picontrol.service
```
