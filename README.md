# Docker UPnP Sync (Shell Version)

A powerful shell script that automatically scans running Docker containers on your local machine and uses the UPnP protocol to create port forwarding rules on your router, enabling external access. It includes state management and a self-healing mechanism.

## ⚠️ Important Security Warning

**Exposing internal services to the public internet is extremely risky.** Ensure your services are secure (strong passwords, authentication, timely updates) and that you fully understand the implications. This project is best suited for trusted home or development networks. **DO NOT use it in a production environment.**

## Features

- **Auto-Discovery**: Automatically scans for running Docker containers with published ports.
- **Smart Sync**: Adds and removes port forwarding rules on your router to match the state of your containers.
- **State Persistence**: Keeps a local record of managed ports to prevent redundant operations.
- **Self-Healing**: If your router reboots or a mapping is lost, the script will automatically detect and recreate the necessary rules.
- **Service-Based**: Runs as a background Systemd service for stability and starts on boot.
- **One-Click Deployment**: An installation script simplifies the entire setup process.

## Prerequisites

- `docker`: The Docker engine.
- `jq`: A command-line JSON processor.
- `miniupnpc`: Provides the `upnpc` command-line tool for router communication.

The installation script will attempt to automatically install `jq` and `miniupnpc` for you. You must have Docker installed beforehand.

## 🚀 One-Click Deployment

1.  Clone this repository onto your Linux server:
    ```bash
    git clone [https://github.com/your_username/docker-upnp-sync.git](https://github.com/your_username/docker-upnp-sync.git)
    cd docker-upnp-sync
    ```

2.  Run the installation script:
    ```bash
    sudo bash install.sh
    ```

The script will handle the rest of the setup automatically.

## Usage and Management

- **Check Service Status**:
  ```bash
  sudo systemctl status docker-upnp-sync
  ```

- **View Live Logs**:
  ```bash
  sudo journalctl -u docker-upnp-sync -f
  ```

- **Stop the Service**:
  ```bash
  sudo systemctl stop docker-upnp-sync
  ```

- **Start the Service**:
  ```bash
  sudo systemctl start docker-upnp-sync
  ```

## Configuration

The configuration file is located at `/etc/docker-upnp-sync/config.env`. You can modify parameters like the check interval.

```
# The interval in seconds between each check.
CHECK_INTERVAL=60

# The description attached to UPnP entries on the router.
UPNP_DESCRIPTION="Docker-UPnP-Sync"
```

## Uninstallation

To completely remove the tool, run the uninstallation script from the project directory:

```bash
sudo bash uninstall.sh
```

## How It Works

The script uses `docker inspect` and `jq` to get a list of required port mappings. It compares this list against a local state file (`/var/lib/docker-upnp-sync/state.json`). Finally, it communicates with the router's UPnP service using the `upnpc` command-line tool to add or delete port mappings. This entire process runs in an infinite loop to ensure the router's state eventually matches the Docker state.
