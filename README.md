# DockerAutoUPnP

Automatically expose your Docker container ports to the internet using **UPnP**.  
This tool provides a one-click installer (`install.sh`) that:

- Watches Docker containers and detects published ports  
- Uses `miniupnpc` to request UPnP port mappings on your router  
- Adds mappings when a container starts, removes them when it stops  
- Runs continuously in the background  

⚠️ **Warning**: UPnP opens ports on your router to the internet.  
Only expose services you really want to make public, and secure them properly.

---

## Features
- **One-command install** with `install.sh`
- **Automatic detection** of published Docker ports
- **Dynamic synchronization**: adds/removes mappings as containers start/stop
- **Self-test** function to check if UPnP works on your router
- **Clean uninstall** removes all containers and files

---

## Requirements
- Linux server (Ubuntu/Debian recommended)
- Docker installed (the script can install it automatically)
- Router with **UPnP enabled**
- Public IP (not behind CGNAT) if you want external access

---

## Quick Start

Run this on your Docker host:

```bash
curl -fsSL -o install.sh https://raw.githubusercontent.com/MrTangLuyao/DockerAutoUPnP/main/install.sh
sudo bash install.sh install --host-ip 192.168.1.101
