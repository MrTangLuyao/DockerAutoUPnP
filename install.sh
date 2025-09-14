#!/bin/bash

# 必须以root权限运行
if [ "$EUID" -ne 0 ]; then
  echo "错误：请使用sudo或以root权限运行此安装脚本。"
  exit 1
fi

echo "--- 开始部署 Docker UPnP Sync 服务 ---"

# 1. 检查和安装依赖
echo "步骤 1/5: 检查并安装依赖 (jq, miniupnpc)..."
if command -v apt-get &> /dev/null; then
    apt-get update >/dev/null
    apt-get install -y jq miniupnpc >/dev/null
elif command -v dnf &> /dev/null; then
    dnf install -y jq miniupnpc >/dev/null
elif command -v yum &> /dev/null; then
    yum install -y jq miniupnpc >/dev/null
else
    echo "错误：不支持的包管理器。请手动安装 'jq' 和 'miniupnpc'。"
    exit 1
fi
echo "依赖安装完成。"

# 2. 复制文件到系统目录
echo "步骤 2/5: 复制脚本和配置文件..."
# 核心脚本
install -m 755 docker-upnp-sync.sh /usr/local/bin/docker-upnp-sync
# 配置文件目录
mkdir -p /etc/docker-upnp-sync
# 复制配置文件模板
if [ ! -f /etc/docker-upnp-sync/config.env ]; then
    cp config.env.example /etc/docker-upnp-sync/config.env
    echo "已创建默认配置文件于 /etc/docker-upnp-sync/config.env，您可以按需修改。"
else
    echo "配置文件已存在，跳过创建。"
fi
echo "文件复制完成。"

# 3. 创建 Systemd 服务
echo "步骤 3/5: 设置 Systemd 服务..."
cp docker-upnp-sync.service /etc/systemd/system/docker-upnp-sync.service
echo "Systemd 服务文件创建完成。"

# 4. 重新加载并启动服务
echo "步骤 4/5: 启动并设置开机自启..."
systemctl daemon-reload
systemctl enable docker-upnp-sync.service
systemctl start docker-upnp-sync.service
echo "服务已启动并设置为开机自启。"

# 5. 显示状态
echo "步骤 5/5: 部署完成！"
echo ""
echo "您可以通过以下命令查看服务状态:"
echo "sudo systemctl status docker-upnp-sync"
echo ""
echo "查看实时日志:"
echo "sudo journalctl -u docker-upnp-sync -f"
echo ""
echo "配置文件位于: /etc/docker-upnp-sync/config.env"
echo "状态文件位于: /var/lib/docker-upnp-sync/state.json"
