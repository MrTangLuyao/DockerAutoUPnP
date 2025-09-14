#!/bin/bash

# This script must be run as root
if [ "$EUID" -ne 0 ]; then
  echo "Error: This script must be run as root or with sudo."
  exit 1
fi

# --- GitHub Repository Details ---
# All required files will be downloaded from here.
GITHUB_USER="MrTangLuyao"
GITHUB_REPO="DockerAutoUPnP"
BRANCH="main"
REPO_BASE_URL="https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/${BRANCH}"

# --- Helper function for downloading ---
download() {
  local url="$1"
  local dest="$2"
  echo "--> Downloading ${url##*/} to ${dest}..."
  if ! curl -sSLf "${url}" -o "${dest}"; then
    echo "Error: Failed to download ${url}. Please check your internet connection and the URL."
    exit 1
  fi
}

echo "--- Starting deployment of Docker UPnP Sync service ---"

# 1. Check and install dependencies
echo "Step 1/5: Checking and installing dependencies (jq, miniupnpc, curl)..."
if command -v apt-get &> /dev/null; then
    apt-get update >/dev/null
    apt-get install -y jq miniupnpc curl >/dev/null
elif command -v dnf &> /dev/null; then
    dnf install -y jq miniupnpc curl >/dev/null
elif command -v yum &> /dev/null; then
    yum install -y jq miniupnpc curl >/dev/null
else
    echo "Error: Unsupported package manager. Please manually install 'jq', 'miniupnpc', and 'curl'."
    exit 1
fi
echo "Dependencies installed."

# 2. Download and install files from GitHub
echo "Step 2/5: Downloading and installing files from GitHub..."

# Download the main script
download "${REPO_BASE_URL}/docker-upnp-sync.sh" "/usr/local/bin/docker-upnp-sync"
chmod 755 "/usr/local/bin/docker-upnp-sync"

# Download the configuration file template (if it doesn't exist)
mkdir -p /etc/docker-upnp-sync
if [ ! -f /etc/docker-upnp-sync/config.env ]; then
    download "${REPO_BASE_URL}/config.env.example" "/etc/docker-upnp-sync/config.env"
    echo "Default configuration file created at /etc/docker-upnp-sync/config.env. You can edit it if needed."
else
    echo "Configuration file already exists, skipping download."
fi
echo "Files installed."

# 3. Set up the Systemd service
echo "Step 3/5: Setting up Systemd service..."
download "${REPO_BASE_URL}/docker-upnp-sync.service" "/etc/systemd/system/docker-upnp-sync.service"
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
