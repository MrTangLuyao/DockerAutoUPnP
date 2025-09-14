#!/bin/bash

# 脚本出错时立即退出
set -e

# --- 默认配置 (可以被 config.env 覆盖) ---
# 状态文件路径
STATE_FILE="/var/lib/docker-upnp-sync/state.json"
# 日志文件路径
LOG_FILE="/var/log/docker-upnp-sync.log"
# 检查间隔（秒）
CHECK_INTERVAL=60
# UPNP 映射的描述
UPNP_DESCRIPTION="Docker-UPnP-Sync"

# --- 函数定义 ---

# 日志记录函数
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# 获取本机IP
get_local_ip() {
    hostname -I | awk '{print $1}'
}

# 获取当前需要映射的端口 (从Docker)
get_desired_ports() {
    docker ps --format "{{.ID}}" | xargs --no-run-if-empty docker inspect | \
    jq -r '
        .[] | .NetworkSettings.Ports | to_entries[] | 
        select(.value != null) | .value[] | 
        select(.HostIp == "0.0.0.0" or .HostIp == "127.0.0.1") |
        "\(.HostPort)/\(.key | split("/") | .[1] | ascii_upcase)"
    ' | sort -u
}

# 清理所有管理的端口
cleanup() {
    log "接收到终止信号，开始清理所有端口映射..."
    if [ ! -f "$STATE_FILE" ]; then
        log "状态文件不存在，无需清理。"
        exit 0
    fi

    # 读取状态文件中的端口进行清理
    jq -r 'keys[]' "$STATE_FILE" | while read -r port_key; do
        port=$(echo "$port_key" | cut -d'/' -f1)
        proto=$(echo "$port_key" | cut -d'/' -f2)
        log "正在移除端口映射: ${port}/${proto}..."
        if upnpc -d "$port" "$proto"; then
            log "成功移除: ${port}/${proto}"
        else
            log "警告: 移除 ${port}/${proto} 失败，可能已被手动移除。"
        fi
    done
    rm -f "$STATE_FILE"
    log "清理完成。"
    exit 0
}

# --- 主逻辑 ---

# 注册信号处理，确保Ctrl+C可以触发清理
trap cleanup SIGINT SIGTERM

# 加载配置文件 (如果存在)
CONFIG_FILE="/etc/docker-upnp-sync/config.env"
if [ -f "$CONFIG_FILE" ]; then
    log "加载配置文件: $CONFIG_FILE"
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

# 创建必要的目录和文件
mkdir -p "$(dirname "$STATE_FILE")"
touch "$STATE_FILE"
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"

LOCAL_IP=$(get_local_ip)
if [ -z "$LOCAL_IP" ]; then
    log "错误: 无法获取本机IP地址，退出。"
    exit 1
fi
log "脚本启动，本机IP: $LOCAL_IP"

# 主循环
while true; do
    log "--- 开始同步检查 ---"

    # 获取期望状态 (Docker) 和当前状态 (State File)
    desired_ports=$(get_desired_ports)
    managed_ports=$(jq -r 'keys[]' "$STATE_FILE")

    # 1. 移除不再需要的端口
    comm -13 <(echo "$desired_ports" | sort) <(echo "$managed_ports" | sort) | while read -r port_key; do
        port=$(echo "$port_key" | cut -d'/' -f1)
        proto=$(echo "$port_key" | cut -d'/' -f2)
        log "检测到不再需要的端口: ${port_key}，正在移除..."
        if upnpc -d "$port" "$proto"; then
            log "成功从路由器移除: ${port}/${proto}"
            # 从状态文件中删除
            temp_state=$(jq "del(.\"$port_key\")" "$STATE_FILE")
            echo "$temp_state" > "$STATE_FILE"
        else
            log "警告: 移除 ${port}/${proto} 失败，将从状态文件中移除记录。"
            temp_state=$(jq "del(.\"$port_key\")" "$STATE_FILE")
            echo "$temp_state" > "$STATE_FILE"
        fi
    done

    # 2. 添加新端口或检查现有端口（自愈）
    echo "$desired_ports" | while read -r port_key; do
        port=$(echo "$port_key" | cut -d'/' -f1)
        proto=$(echo "$port_key" | cut -d'/' -f2)
        
        # 检查路由器上是否存在
        # upnpc -l 的输出格式不稳定，这里采用更直接的方式：尝试获取特定映射
        existing_mapping=$(upnpc -s | grep "TCP ${port} -> ${LOCAL_IP}:${port}" || upnpc -s | grep "UDP ${port} -> ${LOCAL_IP}:${port}")

        if [ -n "$existing_mapping" ]; then
            log "端口映射已存在且正确: ${port_key}"
            # 确保状态文件中有记录
            if ! jq -e ".\"$port_key\"" "$STATE_FILE" > /dev/null; then
                 temp_state=$(jq ". + {\"$port_key\": {\"status\": \"managed\"}}" "$STATE_FILE")
                 echo "$temp_state" > "$STATE_FILE"
            fi
        else
            log "检测到新端口或丢失的映射: ${port_key}，正在添加..."
            if upnpc -a "$LOCAL_IP" "$port" "$port" "$proto" -e "$UPNP_DESCRIPTION"; then
                log "成功添加映射: [WAN]:${port}/${proto} -> ${LOCAL_IP}:${port}"
                # 添加到状态文件
                temp_state=$(jq ". + {\"$port_key\": {\"status\": \"managed\"}}" "$STATE_FILE")
                echo "$temp_state" > "$STATE_FILE"
            else
                log "错误: 添加映射 ${port}/${proto} 失败。"
            fi
        fi
    done

    log "--- 同步完成，等待 ${CHECK_INTERVAL} 秒 ---"
    sleep "$CHECK_INTERVAL"
done
