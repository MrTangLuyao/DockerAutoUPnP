# docker-upnp-onekey

Automatically expose your Docker container ports to the internet using **UPnP**.  
This project provides a one-click installer (`install.sh`) that:

- Watches Docker containers and detects published ports
- Calls `miniupnpc` to request UPnP port mappings on your home router
- Adds mappings when a container starts, removes them when a container stops
- Runs fully automatically in the background

⚠️ **Warning**: UPnP opens ports on your router to the internet.  
Only expose services you intend to make public, and secure them properly.

---

## Features
- **One-command install**: everything packaged in `install.sh`
- **Auto detection**: scans Docker containers for published ports
- **Dynamic sync**: add/remove mappings as containers start/stop
- **Self-test**: built-in command to check if your router’s UPnP works
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
curl -fsSL -o install.sh https://raw.githubusercontent.com/<yourname>/docker-upnp-onekey/main/install.sh
sudo bash install.sh install --host-ip 192.168.1.101
