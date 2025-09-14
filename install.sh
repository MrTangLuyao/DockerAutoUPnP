#!/usr/bin/env bash
# DockerAutoUPnP - one-click installer with self-heal
set -euo pipefail

APP_NAME="docker-upnp"
WORK_DIR="/opt/docker-upnp"
SCAN_INTERVAL_DEFAULT="10"
HOST_IP=""

usage() {
  cat <<EOF
Usage: sudo bash install.sh [command] [options]
Commands: install | uninstall | up | down | status | logs | testmap | help
Options:
  --host-ip <IP>         Override auto-detected LAN IP
  --dir <DIR>            Installation directory (default: /opt/docker-upnp)
  --scan-interval <sec>  Scan interval (default: 10)
EOF
}

CMD="${1:-help}"; shift || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --host-ip) HOST_IP="${2:-}"; shift 2 ;;
    --dir) WORK_DIR="${2:-}"; shift 2 ;;
    --scan-interval) SCAN_INTERVAL_DEFAULT="${2:-}"; shift 2 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

require_root() { [[ "$(id -u)" -eq 0 ]] || { echo "Run as root with sudo"; exit 1; }; }
detect_ip() { [[ -n "$HOST_IP" ]] && echo "$HOST_IP" || ip route get 1.1.1.1 2>/dev/null | awk '/src/{for(i=1;i<=NF;i++)if($i=="src"){print $(i+1)}}'; }
compose_cmd() { if docker compose version >/dev/null 2>&1; then echo "docker compose"; elif command -v docker-compose >/dev/null 2>&1; then echo "docker-compose"; else echo ""; fi; }
ensure_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "[+] Installing Docker..."
    apt-get update
    apt-get install -y ca-certificates curl gnupg lsb-release
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    . /etc/os-release
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME:-$(lsb_release -cs)} stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    systemctl enable --now docker
  fi
}

write_files() {
  mkdir -p "$WORK_DIR"
  cat > "$WORK_DIR/docker-compose.yml" <<YAML
version: "3.8"
services:
  docker-upnp:
    container_name: docker-upnp
    build:
      context: .
      dockerfile: Dockerfile
    network_mode: host
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - docker_upnp_state:/state
    environment:
      HOST_IP: "$(detect_ip)"
      SCAN_INTERVAL: "${SCAN_INTERVAL_DEFAULT}"
      # 自愈阈值：连续失败多少次后清空状态并全量重建
      SELF_HEAL_THRESHOLD: "5"
    restart: unless-stopped

volumes:
  docker_upnp_state:
YAML

  cat > "$WORK_DIR/Dockerfile" <<'DOCKER'
FROM alpine:3.20
RUN apk add --no-cache docker-cli jq miniupnpc bash coreutils iproute2
COPY docker-upnp.sh /usr/local/bin/docker-upnp.sh
RUN chmod +x /usr/local/bin/docker-upnp.sh
ENTRYPOINT ["/usr/local/bin/docker-upnp.sh"]
DOCKER

  # ===== 这里是增强版 docker-upnp.sh（带自愈） =====
  cat > "$WORK_DIR/docker-upnp.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="/state"
STATE_FILE="$STATE_DIR/mappings.json"
FAIL_FILE="$STATE_DIR/fail_streak"
mkdir -p "$STATE_DIR"
[ -f "$STATE_FILE" ] || echo '[]' > "$STATE_FILE"
[ -f "$FAIL_FILE" ] || echo '0' > "$FAIL_FILE"

detect_ip() {
  if [ -n "${HOST_IP:-}" ]; then echo "$HOST_IP"; return; fi
  ip route get 1.1.1.1 2>/dev/null | awk '/src/{for(i=1;i<=NF;i++)if($i=="src"){print $(i+1); exit}}'
}

HOST_ADDR="$(detect_ip)"
if [ -z "$HOST_ADDR" ]; then
  echo "[docker-upnp] ERROR: Cannot detect LAN IP. Set HOST_IP."
  exit 1
fi

SCAN_INTERVAL="${SCAN_INTERVAL:-10}"
SELF_HEAL_THRESHOLD="${SELF_HEAL_THRESHOLD:-5}"

log() { echo "[docker-upnp] $*"; }

router_map_count() {
  # 统计当前路由器的 UPnP 表条目数
  upnpc -l 2>/dev/null | grep -E ' (TCP|UDP) ' | wc -l | tr -d ' '
}

desired_ports() {
  docker ps -q | while read -r CID; do
    [ -n "$CID" ] || continue
    docker inspect "$CID" | jq -r '
      .[0].NetworkSettings.Ports // {} |
      to_entries[]? |
      .key as $k |
      .value[]? |
      select(.HostPort != null and .HostPort != "") |
      ($k | capture("(?<port>[0-9]+)/(?<proto>tcp|udp)")) as $p |
      "\($p.proto):\(.HostPort)"
    ' 2>/dev/null
  done | sort -u
}

read_state() { jq -r '.[]' "$STATE_FILE" 2>/dev/null | sort -u; }
write_state() { jq -n --argjson arr "$(printf '%s\n' "$@" | jq -R . | jq -s .)" '$arr' > "$STATE_FILE".tmp && mv "$STATE_FILE".tmp "$STATE_FILE"; }

inc_fail() { n="$(cat "$FAIL_FILE" 2>/dev/null || echo 0)"; n=$((n+1)); echo "$n" > "$FAIL_FILE"; }
reset_fail() { echo '0' > "$FAIL_FILE"; }
get_fail() { cat "$FAIL_FILE" 2>/dev/null || echo 0; }

add_mapping() {
  local proto="$1" port="$2"
  if upnpc -e "docker-upnp" -a "$HOST_ADDR" "$port" "$port" "$(echo "$proto" | tr a-z A-Z)" >/dev/null 2>&1; then
    log "Added mapping: $proto:$port -> $HOST_ADDR:$port"
    return 0
  else
    log "WARN: add failed: $proto:$port"
    return 1
  fi
}

del_mapping() {
  local proto="$1" port="$2"
  if upnpc -d "$port" "$(echo "$proto" | tr a-z A-Z)" >/dev/null 2>&1; then
    log "Deleted mapping: $proto:$port"
    return 0
  else
    log "WARN: delete failed: $proto:$port"
    return 1
  fi
}

self_heal() {
  log "Self-heal: clearing state and forcing full resync..."
  echo '[]' > "$STATE_FILE"
  reset_fail
}

sync_once() {
  local had_success=0
  mapfile -t desired < <(desired_ports || true)
  mapfile -t current < <(read_state || true)

  local tmp; tmp="$(mktemp -d)"
  printf "%s\n" "${desired[@]:-}" | sort -u > "$tmp/desired"
  printf "%s\n" "${current[@]:-}" | sort -u > "$tmp/current"

  mapfile -t to_add < <(comm -23 "$tmp/desired" "$tmp/current" || true)
  mapfile -t to_del < <(comm -13 "$tmp/desired" "$tmp/current" || true)

  # 执行新增
  for item in "${to_add[@]:-}"; do
    proto="${item%%:*}"; port="${item##*:}"
    if add_mapping "$proto" "$port"; then
      current+=("$item"); had_success=1
    else
      inc_fail
    fi
  done

  # 执行删除
  for item in "${to_del[@]:-}"; do
    proto="${item%%:*}"; port="${item##*:}"
    if del_mapping "$proto" "$port"; then
      # 从 current 移除
      tmpc=(); for c in "${current[@]:-}"; do [ "$c" = "$item" ] || tmpc+=("$c"); done
      current=("${tmpc[@]:-}"); had_success=1
    else
      inc_fail
    fi
  done

  # 如果没有任何成功操作，但“应该有端口”且路由器列表却是空的 => 自愈
  local desired_cnt current_cnt router_cnt
  desired_cnt=$(wc -l < "$tmp/desired" | tr -d ' ')
  current_cnt=$(wc -l < "$tmp/current" | tr -d ' ')
  router_cnt=$(router_map_count || echo 0)

  if [ "$had_success" -eq 0 ]; then
    if [ "$(get_fail)" -ge "$SELF_HEAL_THRESHOLD" ]; then
      log "Failure streak >= ${SELF_HEAL_THRESHOLD} -> trigger self-heal."
      self_heal
    elif [ "$desired_cnt" -gt 0 ] && [ "$router_cnt" -eq 0 ] && [ "$current_cnt" -gt 0 ]; then
      log "Router UPnP table empty but we expect mappings -> trigger self-heal."
      self_heal
    fi
  else
    reset_fail
  fi

  write_state "${current[@]:-}"
  rm -rf "$tmp"
}

log "Host IP: $HOST_ADDR"
log "Monitoring every ${SCAN_INTERVAL}s (self-heal threshold=${SELF_HEAL_THRESHOLD})"

sync_once
while true; do
  sleep "$SCAN_INTERVAL"
  sync_once
done
SCRIPT

  chmod +x "$WORK_DIR/docker-upnp.sh"
}

compose() { (cd "$WORK_DIR" && $(compose_cmd) "$@"); }

case "$CMD" in
  install) require_root; ensure_docker; write_files; compose build; compose up -d; echo "[✓] Installed and running.";;
  uninstall) require_root; compose down || true; rm -rf "$WORK_DIR"; echo "[✓] Uninstalled.";;
  up) require_root; compose up -d;;
  down) require_root; compose down;;
  status) docker ps --filter "name=$APP_NAME";;
  logs) docker logs -f "$APP_NAME";;
  testmap) docker exec -it "$APP_NAME" sh -lc 'upnpc -l | sed -n "1,200p"';;
  help|*) usage;;
esac
