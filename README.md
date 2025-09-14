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
```

---
# 中文版

# DockerAutoUPnP

自动通过 **UPnP** 将你选择暴露端口的Docker容器自动端口映射，从而让其他设备访问。 
常见用途：小型家庭/企业服务器运行docker容器 -> DockerAutoUPnP -> 互联网访问 
本项目提供一个一键安装脚本 (`install.sh`)，功能包括：

- 监控正在运行的 Docker 容器并检测已发布的端口
- 调用 `miniupnpc` 在路由器上请求 UPnP 端口映射
- 在容器启动时自动添加映射，在容器停止时移除映射
- 后台持续运行，无需人工干预

⚠️ **警告**：UPnP 会在路由器上直接打开端口到公网。  
请仅暴露你打算公开的服务，并做好安全措施。

---

## 功能特点
- **自动检测**：自动发现宿主机局域网 IP（无需手动配置）
- **动态同步**：容器启动/停止时自动添加或移除映射
- **自测功能**：内置命令可检测路由器是否支持 UPnP
- **安全清理**：卸载时会移除所有文件与容器

---

## 系统要求
- Linux 服务器（推荐 Ubuntu/Debian）
- 已安装 Docker（脚本可自动安装）
- 路由器已启用 **UPnP**
- 需要公网 IP（不能在 CGNAT 后面）才能从外部访问

---

## 快速开始

在 Docker 宿主机上运行：

```bash
curl -fsSL -o install.sh https://raw.githubusercontent.com/MrTangLuyao/DockerAutoUPnP/main/install.sh
sudo bash install.sh install
```

## 使用方法
```bash
sudo bash install.sh install       # 安装并启动服务
sudo bash install.sh logs          # 查看日志
sudo bash install.sh status        # 检查容器状态
sudo bash install.sh testmap       # 运行 UPnP 自测（临时添加/移除端口）
sudo bash install.sh down          # 停止服务
sudo bash install.sh uninstall     # 完全卸载
```
