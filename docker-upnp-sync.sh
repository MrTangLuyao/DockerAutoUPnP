#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Default Configuration (can be overridden by config.env) ---
# Path to the state file
STATE_FILE="/var/lib/docker-upnp-sync/state.json"
# Path to the log file
LOG_FILE="/var/log/docker-upnp-sync.log"
# Check interval in seconds
CHECK_INTERVAL=60
# Description for the UPnP port mappings on the router
UPNP_DESCRIPTION="Docker-UPnP-Sync"

# --- Function Definitions ---

# Logging function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Get the local IP address of the host
get_local_ip() {
    hostname -I | awk '{print $1}'
}

# Get the desired ports to be mapped (from running Docker containers)
get_desired_ports() {
    docker ps --format "{{.ID}}" | xargs --no-run-if-empty docker inspect | \
    jq -r '
        .[] | .NetworkSettings.Ports | to_entries[] | 
        select(.value != null) | .value[] | 
        select(.HostIp == "0.0.0.0" or .HostIp == "127.0.0.1") |
        "\(.HostPort)/\(.key | split("/") | .[1] | ascii_upcase)"
    ' | sort -u
}

# Clean up all managed ports on script exit
cleanup() {
    log "Termination signal received, cleaning up all port mappings..."
    if [ ! -f "$STATE_FILE" ]; then
        log "State file not found. No cleanup needed."
        exit 0
    fi

    # Read ports from the state file and remove them
    jq -r 'keys[]' "$STATE_FILE" | while read -r port_key; do
        port=$(echo "$port_key" | cut -d'/' -f1)
        proto=$(echo "$port_key" | cut -d'/' -f2)
        log "Removing port mapping: ${port}/${proto}..."
        if upnpc -d "$port" "$proto"; then
            log "Successfully removed: ${port}/${proto}"
        else
            log "Warning: Failed to remove ${port}/${proto}. It might have been removed manually."
        fi
    done
    rm -f "$STATE_FILE"
    log "Cleanup complete."
    exit 0
}

# --- Main Logic ---

# Register signal handler to trigger cleanup on Ctrl+C or termination
trap cleanup SIGINT SIGTERM

# Load configuration file if it exists
CONFIG_FILE="/etc/docker-upnp-sync/config.env"
if [ -f "$CONFIG_FILE" ]; then
    log "Loading configuration from: $CONFIG_FILE"
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

# Create necessary directories and files
mkdir -p "$(dirname "$STATE_FILE")"
touch "$STATE_FILE"
mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"

LOCAL_IP=$(get_local_ip)
if [ -z "$LOCAL_IP" ]; then
    log "Error: Could not determine local IP address. Exiting."
    exit 1
fi
log "Script starting, local IP: $LOCAL_IP"

# Main loop
while true; do
    log "--- Starting sync cycle ---"

    # Get the desired state (from Docker) and the current managed state (from state file)
    desired_ports=$(get_desired_ports)
    managed_ports=$(jq -r 'keys[]' "$STATE_FILE")

    # 1. Remove ports that are no longer needed
    comm -13 <(echo "$desired_ports" | sort) <(echo "$managed_ports" | sort) | while read -r port_key; do
        port=$(echo "$port_key" | cut -d'/' -f1)
        proto=$(echo "$port_key" | cut -d'/' -f2)
        log "Port no longer required: ${port_key}. Removing..."
        if upnpc -d "$port" "$proto"; then
            log "Successfully removed from router: ${port}/${proto}"
            # Remove from state file
            temp_state=$(jq "del(.\"$port_key\")" "$STATE_FILE")
            echo "$temp_state" > "$STATE_FILE"
        else
            log "Warning: Failed to remove ${port}/${proto} from router. Removing from state file anyway."
            temp_state=$(jq "del(.\"$port_key\")" "$STATE_FILE")
            echo "$temp_state" > "$STATE_FILE"
        fi
    done

    # 2. Add new ports or re-add missing ports (self-healing)
    echo "$desired_ports" | while read -r port_key; do
        port=$(echo "$port_key" | cut -d'/' -f1)
        proto=$(echo "$port_key" | cut -d'/' -f2)
        
        # Check if the mapping already exists on the router
        # upnpc -l output is not stable for parsing, so we'll check specifically
        existing_mapping=$(upnpc -s | grep "TCP ${port} -> ${LOCAL_IP}:${port}" || upnpc -s | grep "UDP ${port} -> ${LOCAL_IP}:${port}")

        if [ -n "$existing_mapping" ]; then
            log "Mapping already exists and is correct: ${port_key}"
            # Ensure it's tracked in the state file
            if ! jq -e ".\"$port_key\"" "$STATE_FILE" > /dev/null; then
                 temp_state=$(jq ". + {\"$port_key\": {\"status\": \"managed\"}}" "$STATE_FILE")
                 echo "$temp_state" > "$STATE_FILE"
            fi
        else
            log "New or missing mapping detected: ${port_key}. Adding..."
            if upnpc -a "$LOCAL_IP" "$port" "$port" "$proto" -e "$UPNP_DESCRIPTION"; then
                log "Successfully added mapping: [WAN]:${port}/${proto} -> ${LOCAL_IP}:${port}"
                # Add to state file
                temp_state=$(jq ". + {\"$port_key\": {\"status\": \"managed\"}}" "$STATE_FILE")
                echo "$temp_state" > "$STATE_FILE"
            else
                log "Error: Failed to add mapping for ${port}/${proto}."
            fi
        fi
    done

    log "--- Sync cycle complete, sleeping for ${CHECK_INTERVAL} seconds ---"
    sleep "$CHECK_INTERVAL"
done
