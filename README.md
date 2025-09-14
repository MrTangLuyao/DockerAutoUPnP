# DockerAutoUPnP

Automatically expose your Docker container ports to the internet using **UPnP**.  
This project provides a one-click installer (`install.sh`) that:

- Monitors running Docker containers and detects published ports
- Calls `miniupnpc` to request UPnP port mappings on your home router
- Adds mappings when a container starts, removes them when a container stops
- Runs continuously in the background

⚠️ **Warning**: UPnP opens ports on your router to the internet.  
Only expose services you intend to make public, and secure them properly.

---

## Features
- **Auto detection**: automatically discovers your host LAN IP (no manual IP required)
- **Dynamic sync**: add/remove mappings as containers start/stop
- **Self-test**: built-in command to check if UPnP works on your router
- **Safe cleanup**: uninstall removes all files and containers

---

## Requirements
- Linux server (Ubuntu/Debian recommended)
- Docker installed (the script can install it automatically)
- A home router with **UPnP enabled**
- A real public IP (not behind CGNAT) if you want outside access

---

## Quick Start

Run on your Docker host:

```bash
curl -fsSL -o install.sh https://raw.githubusercontent.com/MrTangLuyao/DockerAutoUPnP/main/install.sh
sudo bash install.sh install
```



## Usage

```bash
sudo bash install.sh install       # Install & start service
sudo bash install.sh logs          # View logs
sudo bash install.sh status        # Check container status
sudo bash install.sh testmap       # Run a UPnP self-test (add/remove a temporary port)
sudo bash install.sh down          # Stop service
sudo bash install.sh uninstall     # Uninstall completely

