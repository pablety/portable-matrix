#!/usr/bin/env bash
# apply-usb-matrix.sh
# Script to run after plugging in the USB to start Matrix stack and configure hostname

set -euo pipefail

# 1. Define where the USB should be mounted
USB_MOUNT="/media/usb"

# 2. Check that USB is mounted
if ! mountpoint -q "$USB_MOUNT"; then
  echo "ERROR: USB not mounted at $USB_MOUNT. Please mount it first."
  exit 1
fi

# 3. Ensure permissions on USB data
echo "Setting permissions on $USB_MOUNT/data..."
sudo chown -R "$USER:$USER" "$USB_MOUNT"

# 4. Add or update miserver.local entry in /etc/hosts
HOSTS_LINE="$({ hostname -I | awk '{print $1}'; } ) miserver.local"
if ! grep -qxF "$HOSTS_LINE" /etc/hosts; then
  echo "Adding host entry: $HOSTS_LINE" 
  sudo sh -c "echo '$HOSTS_LINE' >> /etc/hosts"
else
  echo "Host entry already present: $HOSTS_LINE"
fi

# 5. Change to USB root and restart stack
echo "Starting Docker Compose stack from $USB_MOUNT..."
cd "$USB_MOUNT"
docker compose down || true
docker compose up -d

echo "✅ Matrix stack is running. Access Element Web at http://miserver.local:8080"
