#!/bin/bash

# This script must be run as root
if [ "$EUID" -ne 0 ]; then
  echo "Error: This script must be run as root or with sudo."
  exit 1
fi

echo "--- Starting deployment of Docker UPnP Sync service ---"

# 1. Check and install dependencies
echo "Step 1/5: Checking and installing dependencies (jq, miniupnpc)..."
if command -v apt-get &> /dev/null; then
    apt-get update >/dev/null
    apt-get install -y jq miniupnpc >/dev/null
elif command -v dnf &> /dev/null; then
    dnf install -y jq miniupnpc >/dev/null
elif command -v yum &> /dev/null; then
    yum install -y jq miniupnpc >/dev/null
else
    echo "Error: Unsupported package manager. Please manually install 'jq' and 'miniupnpc'."
    exit 1
fi
echo "Dependencies installed."

# 2. Copy files to system directories
echo "Step 2/5: Copying script and configuration files..."
# Core script
install -m 755 docker-upnp-sync.sh /usr/local/bin/docker-upnp-sync
# Configuration directory
mkdir -p /etc/docker-upnp-sync
# Copy config template if no config exists
if [ ! -f /etc/docker-upnp-sync/config.env ]; then
    cp config.env.example /etc/docker-upnp-sync/config.env
    echo "Default configuration file created at /etc/docker-upnp-sync/config.env. You can edit it if needed."
else
    echo "Configuration file already exists, skipping creation."
fi
echo "Files copied."

# 3. Set up the Systemd service
echo "Step 3/5: Setting up Systemd service..."
cp docker-upnp-sync.service /etc/systemd/system/docker-upnp-sync.service
echo "Systemd service file created."

# 4. Reload daemon and start the service
echo "Step 4/5: Starting and enabling the service..."
systemctl daemon-reload
systemctl enable docker-upnp-sync.service
systemctl start docker-upnp-sync.service
echo "Service started and enabled to start on boot."

# 5. Display status
echo "Step 5/5: Deployment complete!"
echo ""
echo "You can check the service status with:"
echo "sudo systemctl status docker-upnp-sync"
echo ""
echo "To view live logs, use:"
echo "sudo journalctl -u docker-upnp-sync -f"
echo ""
echo "Configuration file: /etc/docker-upnp-sync/config.env"
echo "State file: /var/lib/docker-upnp-sync/state.json"
