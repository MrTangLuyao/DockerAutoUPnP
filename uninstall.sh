#!/bin/bash

# This script must be run as root
if [ "$EUID" -ne 0 ]; then
  echo "Error: This script must be run as root or with sudo."
  exit 1
fi

echo "--- Uninstalling Docker UPnP Sync service ---"

# 1. Stop and disable the service
echo "Stopping and disabling Systemd service..."
systemctl stop docker-upnp-sync.service || true
systemctl disable docker-upnp-sync.service || true
echo "Service stopped."

# 2. Remove files
echo "Removing files..."
rm -f /etc/systemd/system/docker-upnp-sync.service
rm -f /usr/local/bin/docker-upnp-sync
rm -rf /etc/docker-upnp-sync
# Ask before deleting state and log files
read -p "Do you want to delete state and log files? (/var/lib/docker-upnp-sync, /var/log/docker-upnp-sync.log) [y/N]: " choice
case "$choice" in
  y|Y )
    rm -rf /var/lib/docker-upnp-sync
    rm -f /var/log/docker-upnp-sync.log
    echo "State and log files have been deleted."
    ;;
  * )
    echo "State and log files have been kept."
    ;;
esac

# 3. Reload Systemd
systemctl daemon-reload

echo "--- Uninstallation complete ---"
echo "Note: Dependencies 'jq' and 'miniupnpc' were not removed. You may remove them manually if they are no longer needed."
