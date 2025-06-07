#!/bin/bash

# NiPux Ethernet Monitor Service
# Monitors ethernet connection and manages WiFi provisioning fallback
# Runs as a systemd service to provide automatic network management

set -euo pipefail

# Configuration
CONFIG_DIR="/etc/nipux"
LOG_FILE="/var/log/nipux/ethernet-monitor.log"
WIFI_PROVISIONING_SERVICE="nipux-wifi-provisioning"
CHECK_INTERVAL=10  # seconds
ETHERNET_TIMEOUT=30  # seconds to wait for ethernet before starting WiFi

# Logging functions
log_info() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] $1" | tee -a "$LOG_FILE"
}

log_warning() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [WARNING] $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] $1" | tee -a "$LOG_FILE"
}

# Check if ethernet is connected and has internet
check_ethernet_connection() {
    local ethernet_interfaces
    local connected_interface=""
    
    # Find ethernet interfaces (eth*, enp*, ens*, etc.)
    ethernet_interfaces=$(ip link show | grep -E "eth|enp|ens" | grep "state UP" | cut -d: -f2 | tr -d ' ' || true)
    
    if [[ -z "$ethernet_interfaces" ]]; then
        log_info "No active ethernet interfaces found"
        return 1
    fi
    
    # Check each interface for connectivity
    for interface in $ethernet_interfaces; do
        log_info "Checking ethernet interface: $interface"
        
        # Check if interface has an IP address
        if ip addr show "$interface" | grep -q "inet "; then
            local ip_addr=$(ip addr show "$interface" | grep "inet " | head -1 | awk '{print $2}' | cut -d/ -f1)
            log_info "Interface $interface has IP: $ip_addr"
            
            # Test internet connectivity through this interface
            if ping -c 1 -W 5 -I "$interface" 8.8.8.8 >/dev/null 2>&1; then
                log_info "Ethernet connection confirmed via $interface"
                echo "$interface" > "$CONFIG_DIR/active-ethernet"
                return 0
            else
                log_warning "Interface $interface has IP but no internet connectivity"
            fi
        else
            log_info "Interface $interface has no IP address"
        fi
    done
    
    log_info "No functional ethernet connection found"
    rm -f "$CONFIG_DIR/active-ethernet"
    return 1
}

# Check if WiFi provisioning is needed
wifi_provisioning_needed() {
    # If we have ethernet, no WiFi provisioning needed
    if check_ethernet_connection; then
        return 1
    fi
    
    # Check if WiFi is already connected
    if nmcli -t -f TYPE,STATE dev | grep -q "wifi:connected"; then
        log_info "WiFi already connected, no provisioning needed"
        echo "wifi-connected" > "$CONFIG_DIR/network-status"
        return 1
    fi
    
    log_info "No ethernet or WiFi connection - WiFi provisioning needed"
    echo "needs-provisioning" > "$CONFIG_DIR/network-status"
    return 0
}

# Start WiFi provisioning service
start_wifi_provisioning() {
    log_info "Starting WiFi provisioning service..."
    
    if systemctl is-active --quiet "$WIFI_PROVISIONING_SERVICE"; then
        log_info "WiFi provisioning service already running"
        return 0
    fi
    
    if systemctl start "$WIFI_PROVISIONING_SERVICE"; then
        log_info "WiFi provisioning service started successfully"
        echo "provisioning-active" > "$CONFIG_DIR/network-status"
        return 0
    else
        log_error "Failed to start WiFi provisioning service"
        return 1
    fi
}

# Stop WiFi provisioning service
stop_wifi_provisioning() {
    log_info "Stopping WiFi provisioning service..."
    
    if ! systemctl is-active --quiet "$WIFI_PROVISIONING_SERVICE"; then
        log_info "WiFi provisioning service not running"
        return 0
    fi
    
    if systemctl stop "$WIFI_PROVISIONING_SERVICE"; then
        log_info "WiFi provisioning service stopped successfully"
        return 0
    else
        log_error "Failed to stop WiFi provisioning service"
        return 1
    fi
}

# Main monitoring loop
monitor_network() {
    log_info "Starting ethernet monitoring service"
    
    # Create necessary directories
    mkdir -p "$(dirname "$LOG_FILE")"
    mkdir -p "$CONFIG_DIR"
    
    # Initial state
    local provisioning_active=false
    
    while true; do
        log_info "Checking network connectivity..."
        
        if check_ethernet_connection; then
            # Ethernet is connected
            echo "ethernet-connected" > "$CONFIG_DIR/network-status"
            
            if $provisioning_active; then
                log_info "Ethernet connected - stopping WiFi provisioning"
                stop_wifi_provisioning
                provisioning_active=false
            fi
            
        elif nmcli -t -f TYPE,STATE dev | grep -q "wifi:connected"; then
            # WiFi is connected
            echo "wifi-connected" > "$CONFIG_DIR/network-status"
            
            if $provisioning_active; then
                log_info "WiFi connected - stopping WiFi provisioning"
                stop_wifi_provisioning
                provisioning_active=false
            fi
            
        else
            # No network connection
            echo "no-connection" > "$CONFIG_DIR/network-status"
            
            if ! $provisioning_active; then
                log_info "No network connection - starting WiFi provisioning"
                if start_wifi_provisioning; then
                    provisioning_active=true
                fi
            fi
        fi
        
        sleep "$CHECK_INTERVAL"
    done
}

# Handle cleanup on exit
cleanup() {
    log_info "Ethernet monitor service stopping..."
    stop_wifi_provisioning
    exit 0
}

trap cleanup SIGTERM SIGINT

# Main entry point
main() {
    case "${1:-monitor}" in
        "monitor")
            monitor_network
            ;;
        "check")
            if check_ethernet_connection; then
                echo "Ethernet connected"
                exit 0
            elif nmcli -t -f TYPE,STATE dev | grep -q "wifi:connected"; then
                echo "WiFi connected"
                exit 0
            else
                echo "No connection"
                exit 1
            fi
            ;;
        "status")
            if [[ -f "$CONFIG_DIR/network-status" ]]; then
                cat "$CONFIG_DIR/network-status"
            else
                echo "unknown"
            fi
            ;;
        *)
            echo "Usage: $0 [monitor|check|status]"
            exit 1
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi