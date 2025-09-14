
---

# 📄 install.sh (English, with auto IP detection)

```bash
#!/usr/bin/env bash
# DockerAutoUPnP - one-click installer
# Automatically maps Docker container ports to your router via UPnP

set -euo pipefail

APP_NAME="docker-upnp"
WORK_DIR="/opt/docker-upnp"
SCAN_INTERVAL_DEFAULT="10"
HOST_IP=""   # will be auto-detected

usage() {
  cat <<EOF
Usage: sudo bash install.sh [command] [options]

Commands:
  install      Install and start DockerAutoUPnP
  uninstall    Stop and remove everything
  up           Start service only
  down         Stop service only
  status       Show container status
  logs         Follow logs
  testmap      Run a temporary UPnP mapping test
  help         Show this help

Options:
  --host-ip <IP>         Override auto-detected LAN IP
  --dir <DIR>            Installation directory (default: /opt/docker-upnp)
  --scan-interval <sec>  Scan interval (default: 10)
EOF
}

CMD="${1:-help}"; shift || true
while [[ $# -gt 0 ]]; do
  case "$1" in
    --host-ip) HOST_IP="$2"; shift 2 ;;
    --dir) WORK_DIR="$2"; shift 2 ;;
    --scan-interval) SCAN_INTERVAL_DEFAULT="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

require_root() { [[ "$(id -u)" -eq 0 ]] || { echo "Run as root with sudo"; exit 1; }; }

detect_ip() {
  if [[ -n "$HOST_IP" ]]; then echo "$HOST_IP"; return; fi
  ip route get 1.1.1.1 2>/dev/null | awk '/src/ {for(i=1;i<=NF;i++){if($i=="src"){print $(i+1); exit}}}'
}

compose_cmd() {
  if docker compose version >/dev/null 2>&1; then echo "docker compose"
  elif docker-compose version >/dev/null 2>&1; then echo "docker-compose"
  else echo ""; fi
}

ensure_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "[+] Installing Docker..."
    apt-get update
    apt-get install -y ca-certificates curl gnupg lsb-release
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    . /etc/os-release
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      ${UBUNTU_CODENAME:-$(lsb_release -cs)} stable" | tee /etc/apt/sources.list.d/docker.list >/dev/null
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

  cat > "$WORK_DIR/docker-upnp.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="/state"
STATE_FILE="$STATE_DIR/mappings.json"
mkdir -p "$STATE_DIR"
[ -f "$STATE_FILE" ] || echo '[]' > "$STATE_FILE"

detect_ip() {
  if [ -n "${HOST_IP:-}" ]; then echo "$HOST_IP"; return; fi
  ip route get 1.1.1.1 2>/dev/null | awk '/src/ {for(i=1;i<=NF;i++){if($i=="src"){print $(i+1); exit}}}'
}

HOST_ADDR="$(detect_ip)"
if [ -z "$HOST_ADDR" ]; then
  echo "[docker-upnp] ERROR: Cannot detect LAN IP. Set HOST_IP."
  exit 1
fi

SCAN_INTERVAL="${SCAN_INTERVAL:-10}"
log() { echo "[docker-upnp] $*"; }

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

add_mapping() { upnpc -e "docker-upnp" -a "$HOST_ADDR" "$2" "$2" "$(echo "$1" | tr a-z A-Z)" >/dev/null 2>&1 && log "Added $1:$2"; }
del_mapping() { upnpc -d "$2" "$(echo "$1" | tr a-z A-Z)" >/dev/null 2>&1 && log "Deleted $1:$2"; }

sync_once() {
  mapfile -t desired < <(desired_ports || true)
  mapfile -t current < <(read_state || true)

  tmp="$(mktemp -d)"
  printf "%s\n" "${desired[@]:-}" | sort -u > "$tmp/desired"
  printf "%s\n" "${current[@]:-}" | sort -u > "$tmp/current"

  mapfile -t to_add < <(comm -23 "$tmp/desired" "$tmp/current" || true)
  mapfile -t to_del < <(comm -13 "$tmp/desired" "$tmp/current" || true)

  for item in "${to_add[@]:-}"; do proto="${item%%:*}"; port="${item##*:}"; add_mapping "$proto" "$port"; current+=("$item"); done
  for item in "${to_del[@]:-}"; do proto="${item%%:*}"; port="${item##*:}"; del_mapping "$proto" "$port"; current=("${current[@]/$item}"); done

  write_state "${current[@]:-}"
  rm -rf "$tmp"
}

log "Host IP: $HOST_ADDR"
log "Monitoring every ${SCAN_INTERVAL}s"

sync_once
while true; do sleep "$SCAN_INTERVAL"; sync_once; done
SCRIPT

  chmod +x "$WORK_DIR/docker-upnp.sh"
}

compose() { (cd "$WORK_DIR" && $(compose_cmd) "$@"); }

case "$CMD" in
  install) require_root; ensure_docker; write_files; compose build; compose up -d; echo "[✓] Installed and running." ;;
  uninstall) require_root; compose down || true; rm -rf "$WORK_DIR"; echo "[✓] Uninstalled." ;;
  up) require_root; compose up -d ;;
  down) require_root; compose down ;;
  status) docker ps --filter "name=$APP_NAME" ;;
  logs) docker logs -f $APP_NAME ;;
  testmap) docker exec -it $APP_NAME sh -lc 'upnpc -l' ;;
  help|*) usage ;;
esac
