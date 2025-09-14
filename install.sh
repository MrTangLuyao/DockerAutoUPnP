cat >/opt/docker-upnp/docker-upnp.sh <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail

STATE_DIR="/state"
STATE_FILE="$STATE_DIR/mappings.json"
FAIL_FILE="$STATE_DIR/fail_streak"
LAST_HEAL_FILE="$STATE_DIR/last_heal_ts"
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
SELF_HEAL_COOLDOWN="${SELF_HEAL_COOLDOWN:-60}" # seconds

log() { echo "[docker-upnp] $*"; }

to_int() {
  case "${1:-}" in ''|*[!0-9]*) echo 0 ;; *) echo "$1" ;; esac
}
get_now() { date +%s; }

router_map_count() {
  local n
  n="$(upnpc -l 2>/dev/null | grep -E ' (TCP|UDP) ' | wc -l | tr -d ' ' || true)"
  echo "$(to_int "$n")"
}

# --- 强化版端口收集，只产出规范的 "tcp:12345" / "udp:12345" ---
desired_ports() {
  docker ps -q | while read -r CID; do
    [ -n "$CID" ] || continue
    docker inspect "$CID" | jq -r '
      .[0].NetworkSettings.Ports // {} |
      to_entries[]? |
      .key as $k |
      .value[]? |
      (.HostPort // "") as $hp |
      select($hp != "") |
      ($k | capture("(?<port>[0-9]+)/(?<proto>(?i)tcp|udp)")) as $p |
      "\($p.proto|ascii_downcase):\($hp)"
    ' 2>/dev/null
  done \
  | awk '/^(tcp|udp):[0-9]+$/' \
  | sort -u
}

read_state() { jq -r '.[]' "$STATE_FILE" 2>/dev/null | awk '/^(tcp|udp):[0-9]+$/' | sort -u; }
write_state() { jq -n --argjson arr "$(printf '%s\n' "$@" | awk '/^(tcp|udp):[0-9]+$/' | jq -R . | jq -s .)" '$arr' > "$STATE_FILE".tmp && mv "$STATE_FILE".tmp "$STATE_FILE"; }

get_fail() { to_int "$(cat "$FAIL_FILE" 2>/dev/null || echo 0)"; }
inc_fail() { echo "$(( $(get_fail) + 1 ))" > "$FAIL_FILE"; }
reset_fail() { echo 0 > "$FAIL_FILE"; }

can_heal_now() {
  local last now diff
  last="$(to_int "$(cat "$LAST_HEAL_FILE" 2>/dev/null || echo 0)")"
  now="$(get_now)"
  diff=$(( now - last ))
  [ "$diff" -ge "$(to_int "$SELF_HEAL_COOLDOWN")" ]
}
mark_heal_time() { echo "$(get_now)" > "$LAST_HEAL_FILE"; }

valid_pair() {
  local proto="$1" port="$2"
  [[ "$proto" =~ ^(tcp|udp)$ ]] && [[ "$port" =~ ^[0-9]+$ ]]
}

add_mapping() {
  local proto="$1" port="$2"
  if ! valid_pair "$proto" "$port"; then
    log "SKIP invalid add target: '$proto:$port'"
    return 0
  fi
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
  if ! valid_pair "$proto" "$port"; then
    log "SKIP invalid delete target: '$proto:$port'"
    return 0
  fi
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
  mark_heal_time
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

  for item in "${to_add[@]:-}"; do
    proto="${item%%:*}"; port="${item##*:}"
    if add_mapping "$proto" "$port"; then
      current+=("$item"); had_success=1
    else
      inc_fail
    fi
  done

  for item in "${to_del[@]:-}"; do
    proto="${item%%:*}"; port="${item##*:}"
    if del_mapping "$proto" "$port"; then
      tmpc=(); for c in "${current[@]:-}"; do [ "$c" = "$item" ] || tmpc+=("$c"); done
      current=("${tmpc[@]:-}"); had_success=1
    else
      inc_fail
    fi
  done

  local desired_cnt current_cnt router_cnt fail_cnt thres
  desired_cnt="$(to_int "$(wc -l < "$tmp/desired" 2>/dev/null || echo 0)")"
  current_cnt="$(to_int "$(wc -l < "$tmp/current" 2>/dev/null || echo 0)")"
  router_cnt="$(router_map_count)"
  fail_cnt="$(get_fail)"
  thres="$(to_int "$SELF_HEAL_THRESHOLD")"

  if [ "$had_success" -eq 0 ]; then
    if [ "$fail_cnt" -ge "$thres" ] && can_heal_now; then
      log "Failure streak >= $thres (=$fail_cnt), cooldown ok -> trigger self-heal."
      self_heal
    elif [ "$desired_cnt" -gt 0 ] && [ "$router_cnt" -eq 0 ] && [ "$current_cnt" -gt 0 ] && can_heal_now; then
      log "Router table empty while mappings expected (desired=$desired_cnt,current=$current_cnt) -> self-heal."
      self_heal
    fi
  else
    reset_fail
  fi

  write_state "${current[@]:-}"
  rm -rf "$tmp"
}

log "Host IP: $HOST_ADDR"
log "Monitoring every ${SCAN_INTERVAL}s (self-heal threshold=${SELF_HEAL_THRESHOLD}, cooldown=${SELF_HEAL_COOLDOWN}s)"

sync_once
while true; do
  sleep "$SCAN_INTERVAL"
  sync_once
done
SCRIPT

# 赋权并重启容器使之生效
chmod +x /opt/docker-upnp/docker-upnp.sh
cd /opt/docker-upnp
docker compose build --no-cache
docker compose up -d
sleep 4
docker logs --since=30s docker-upnp
