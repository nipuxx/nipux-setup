#!/bin/bash

# NiPux Setup - Ethernet-First Network Management System
# Monitors ethernet connection and provides WiFi fallback when disconnected
# Robust, automatic network provisioning for headless servers

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Global sudo command variable
SUDO_CMD=""

# Setup banner
show_banner() {
    cat << 'EOF'
███╗   ██╗██╗██████╗ ██╗   ██╗██╗  ██╗
████╗  ██║██║██╔══██╗██║   ██║╚██╗██╔╝
██╔██╗ ██║██║██████╔╝██║   ██║ ╚███╔╝ 
██║╚██╗██║██║██╔═══╝ ██║   ██║ ██╔██╗ 
██║ ╚████║██║██║     ╚██████╔╝██╔╝ ██╗
╚═╝  ╚═══╝╚═╝╚═╝      ╚═════╝ ╚═╝  ╚═╝

Ethernet-First Network Management System
========================================
Auto-detects ethernet connection, provides WiFi fallback
EOF
}

# Check if running as root
check_permissions() {
    if [[ $EUID -eq 0 ]]; then
        log_info "Running as root - will handle permissions appropriately"
        SUDO_CMD=""
    else
        log_info "Running as user - will use sudo when needed"
        SUDO_CMD="sudo"
        
        # Test sudo access
        if ! $SUDO_CMD -n true 2>/dev/null; then
            log_info "This script requires sudo access. You may be prompted for your password."
            $SUDO_CMD -v || {
                log_error "Failed to obtain sudo access"
                exit 1
            }
        fi
    fi
}

# Detect system information
detect_system() {
    log_info "Detecting system information..."
    
    if [[ ! -f /etc/os-release ]]; then
        log_error "Cannot detect OS"
        exit 1
    fi
    
    . /etc/os-release
    if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
        log_error "Unsupported OS: $ID. This script supports Ubuntu/Debian only."
        exit 1
    fi
    
    log_success "Detected OS: $ID $VERSION_ID"
    
    # Check for wireless hardware and interfaces
    log_info "Checking for wireless hardware..."
    
    # First check if wireless hardware exists
    local wireless_hardware_found=false
    if lspci | grep -i "network\|wireless\|wifi" | grep -v "Ethernet"; then
        log_info "Found wireless hardware in PCI devices"
        wireless_hardware_found=true
    elif lsusb | grep -i "wireless\|wifi\|802.11"; then
        log_info "Found wireless hardware in USB devices" 
        wireless_hardware_found=true
    elif dmesg | grep -i "wireless\|wifi\|802.11" | head -3; then
        log_info "Found wireless references in kernel messages"
        wireless_hardware_found=true
    fi
    
    # Try to find wireless interfaces
    local wireless_interface=""
    if iw dev 2>/dev/null | grep -q "Interface"; then
        wireless_interface=$(iw dev | awk '$1=="Interface"{print $2}' | head -1)
        log_success "Found active wireless interface: $wireless_interface"
    elif ip link show | grep -E "wlan|wlp|wifi"; then
        wireless_interface=$(ip link show | grep -E "wlan|wlp|wifi" | head -1 | cut -d: -f2 | tr -d ' ')
        log_info "Found potential wireless interface: $wireless_interface"
    elif ls /sys/class/net/ | grep -E "wlan|wlp|wifi"; then
        wireless_interface=$(ls /sys/class/net/ | grep -E "wlan|wlp|wifi" | head -1)
        log_info "Found wireless interface in /sys/class/net: $wireless_interface"
    fi
    
    # If no interface found but hardware exists, try to load drivers
    if [[ -z "$wireless_interface" ]] && [[ "$wireless_hardware_found" == "true" ]]; then
        log_warning "Wireless hardware found but no interface detected. Attempting to load drivers..."
        
        # Install wireless drivers if not present
        $SUDO_CMD apt-get update -qq 2>/dev/null || true
        $SUDO_CMD apt-get install -y linux-firmware wireless-tools wpasupplicant rfkill 2>/dev/null || true
        
        # Check if wireless is blocked by rfkill
        if command -v rfkill >/dev/null 2>&1; then
            log_info "Checking for blocked wireless interfaces..."
            $SUDO_CMD rfkill unblock wifi 2>/dev/null || true
            $SUDO_CMD rfkill unblock all 2>/dev/null || true
        fi
        
        # Try to bring up wireless interfaces
        for iface in $(ls /sys/class/net/ 2>/dev/null); do
            if [[ -d "/sys/class/net/$iface/wireless" ]]; then
                log_info "Found wireless capability on interface: $iface"
                $SUDO_CMD ip link set "$iface" up 2>/dev/null || true
                wireless_interface="$iface"
                break
            fi
        done
        
        # Reload network modules
        $SUDO_CMD modprobe cfg80211 2>/dev/null || true
        $SUDO_CMD modprobe mac80211 2>/dev/null || true
        
        # Wait a moment and check again
        sleep 2
        if iw dev 2>/dev/null | grep -q "Interface"; then
            wireless_interface=$(iw dev | awk '$1=="Interface"{print $2}' | head -1)
            log_success "Successfully activated wireless interface: $wireless_interface"
        fi
    fi
    
    # Final check
    if [[ -z "$wireless_interface" ]]; then
        if [[ "$wireless_hardware_found" == "true" ]]; then
            log_error "Wireless hardware detected but no working interface found."
            log_info "This may require specific drivers for your hardware."
            log_info "Try running: sudo lshw -C network"
            exit 1
        else
            log_error "No wireless hardware found on this system."
            log_info "This system requires a WiFi adapter to function."
            exit 1
        fi
    fi
    
    log_success "Wireless interface ready: $wireless_interface"
}

# Install dependencies using the existing script
install_dependencies() {
    log_info "Installing system dependencies..."
    
    if [[ -f "$SCRIPT_DIR/install-dependencies.sh" ]]; then
        log_info "Running dependency installer..."
        bash "$SCRIPT_DIR/install-dependencies.sh"
    else
        log_warning "Dependency installer not found, attempting manual installation..."
        
        # Update package list
        $SUDO_CMD apt-get update -qq || log_warning "Could not update package list"
        
        # Install essential packages
        local packages=(
            "hostapd" "dnsmasq" "nginx-light" "php-fpm" "php-cli"
            "iw" "wireless-tools" "rfkill" "wpasupplicant" 
            "network-manager" "bridge-utils" "iptables" "net-tools"
        )
        
        for package in "${packages[@]}"; do
            if ! dpkg -l | grep -q "^ii  $package "; then
                log_info "Installing $package..."
                $SUDO_CMD apt-get install -y "$package" || log_warning "Failed to install $package"
            fi
        done
    fi
    
    log_success "Dependencies installed"
}

# Setup ethernet monitoring system
setup_ethernet_monitoring() {
    log_info "Setting up ethernet monitoring system..."
    
    # Create configuration directory
    $SUDO_CMD mkdir -p /etc/nipux
    $SUDO_CMD mkdir -p /var/log/nipux
    
    # Copy ethernet monitor script
    $SUDO_CMD cp "$SCRIPT_DIR/ethernet-monitor.sh" /usr/local/bin/nipux-ethernet-monitor
    $SUDO_CMD chmod +x /usr/local/bin/nipux-ethernet-monitor
    
    # Create ethernet monitoring service
    $SUDO_CMD tee /etc/systemd/system/nipux-ethernet-monitor.service > /dev/null << 'EOF'
[Unit]
Description=NiPux Ethernet Monitor Service
After=network.target NetworkManager.service
Wants=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/nipux-ethernet-monitor monitor
Restart=always
RestartSec=5
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    log_success "Ethernet monitoring system configured"
}

# Setup WiFi provisioning system (modified for new architecture)
setup_wifi_provisioning() {
    log_info "Setting up WiFi provisioning system..."
    
    if [[ -f "$SCRIPT_DIR/setup-wifi-provisioning.sh" ]]; then
        log_info "Running WiFi provisioning setup..."
        
        # Modify the WiFi provisioning setup to work with ethernet monitoring
        # Create a wrapper service that can be controlled by ethernet monitor
        $SUDO_CMD tee /etc/systemd/system/nipux-wifi-provisioning.service > /dev/null << 'EOF'
[Unit]
Description=NiPux WiFi Provisioning Service
After=network.target
ConditionPathExists=!/etc/nipux/ethernet-connected

[Service]
Type=forking
ExecStart=/bin/bash -c 'systemctl start wifi-provisioning'
ExecStop=/bin/bash -c 'systemctl stop wifi-provisioning'
RemainAfterExit=yes
Restart=no

[Install]
WantedBy=multi-user.target
EOF
        
        # Run the original WiFi provisioning setup
        bash "$SCRIPT_DIR/setup-wifi-provisioning.sh"
        
        # Disable automatic startup of original service (will be controlled by ethernet monitor)
        $SUDO_CMD systemctl disable wifi-provisioning 2>/dev/null || true
        
    else
        log_error "WiFi provisioning setup script not found!"
        exit 1
    fi
    
    log_success "WiFi provisioning system configured"
}

# Setup WiFi connect (balena) as fallback
setup_wifi_connect_fallback() {
    log_info "Setting up WiFi Connect as fallback..."
    
    if [[ -f "$SCRIPT_DIR/setup-wifi-connect.sh" ]]; then
        log_info "Running WiFi Connect setup..."
        # Run in background to avoid blocking
        bash "$SCRIPT_DIR/setup-wifi-connect.sh" || log_warning "WiFi Connect setup failed, continuing with main system"
    else
        log_warning "WiFi Connect setup script not found, skipping fallback"
    fi
}

# Fix any permission issues
fix_permissions() {
    log_info "Fixing file permissions..."
    
    # Ensure all scripts are executable
    find "$SCRIPT_DIR" -name "*.sh" -exec chmod +x {} \;
    
    # Fix common permission issues
    if [[ -d "/var/www/wifi-setup" ]]; then
        $SUDO_CMD chown -R www-data:www-data /var/www/wifi-setup 2>/dev/null || true
        $SUDO_CMD chmod -R 755 /var/www/wifi-setup 2>/dev/null || true
    fi
    
    if [[ -d "/etc/wifi-provisioning" ]]; then
        $SUDO_CMD chmod -R 755 /etc/wifi-provisioning 2>/dev/null || true
    fi
    
    log_success "Permissions fixed"
}

# Enable services
enable_services() {
    log_info "Enabling system services..."
    
    # Reload systemd daemon
    $SUDO_CMD systemctl daemon-reload
    
    # Enable ethernet monitoring service (main controller)
    if [[ -f "/etc/systemd/system/nipux-ethernet-monitor.service" ]]; then
        $SUDO_CMD systemctl enable nipux-ethernet-monitor.service
        log_success "Ethernet monitoring service enabled"
    fi
    
    # Enable WiFi provisioning wrapper service
    if [[ -f "/etc/systemd/system/nipux-wifi-provisioning.service" ]]; then
        $SUDO_CMD systemctl enable nipux-wifi-provisioning.service
        log_success "WiFi provisioning wrapper service enabled"
    fi
    
    # Enable monitoring service if it exists
    if [[ -f "/etc/systemd/system/wifi-provisioning-health.timer" ]]; then
        $SUDO_CMD systemctl enable wifi-provisioning-health.timer
        $SUDO_CMD systemctl start wifi-provisioning-health.timer
        log_success "Health monitoring enabled"
    fi
    
    # Note: Original wifi-provisioning service is managed by ethernet monitor
    log_info "Main WiFi provisioning service will be controlled by ethernet monitor"
}

# Create helpful scripts
create_helper_scripts() {
    log_info "Creating helper scripts..."
    
    # Create status check script
    cat > "$SCRIPT_DIR/status.sh" << 'EOF'
#!/bin/bash
# Quick status check for NiPux Network Management System

echo "=== NiPux Network Management Status ==="
echo

# Check ethernet connection
ethernet_status=$(sudo /usr/local/bin/nipux-ethernet-monitor check 2>/dev/null || echo "No connection")
echo "Network Status: $ethernet_status"

echo

# Check ethernet interfaces
if ip link show | grep -E "eth|enp|ens" | grep "state UP" >/dev/null; then
    echo "✓ Ethernet: Interface available"
    ip link show | grep -E "eth|enp|ens" | grep "state UP" | cut -d: -f2 | while read iface; do
        if ip addr show "$iface" | grep -q "inet "; then
            ip_addr=$(ip addr show "$iface" | grep "inet " | head -1 | awk '{print $2}' | cut -d/ -f1)
            echo "  Interface $iface: $ip_addr"
        fi
    done
else
    echo "✗ Ethernet: No active interfaces"
fi

echo

# Check WiFi connection
if nmcli -t -f TYPE,STATE dev | grep -q "wifi:connected"; then
    echo "✓ WiFi: Connected"
    nmcli -t -f DEVICE,CONNECTION dev status | grep wifi | head -1
else
    echo "✗ WiFi: Not connected"
fi

echo

# Check monitoring service status
if systemctl is-active --quiet nipux-ethernet-monitor 2>/dev/null; then
    echo "✓ Ethernet Monitor: Running"
else
    echo "✗ Ethernet Monitor: Not running"
fi

# Check WiFi provisioning status
if systemctl is-active --quiet wifi-provisioning 2>/dev/null; then
    echo "✓ WiFi Provisioning: Active (setup mode)"
    hostname=$(hostname)
    echo "  SSID: ${hostname}-setup"
    echo "  IP: 192.168.4.1"
else
    echo "✗ WiFi Provisioning: Inactive"
fi

echo

# Show network status from file
if [[ -f /etc/nipux/network-status ]]; then
    echo "Current Status: $(cat /etc/nipux/network-status)"
else
    echo "Status: Unknown"
fi

echo

# Show recent logs
echo "Recent logs:"
sudo journalctl -u nipux-ethernet-monitor --no-pager -n 3 2>/dev/null || echo "No recent logs"
EOF
    chmod +x "$SCRIPT_DIR/status.sh"
    
    # Create reset script
    cat > "$SCRIPT_DIR/reset.sh" << 'EOF'
#!/bin/bash
# Force reset to WiFi provisioning setup mode

echo "Forcing NiPux system to WiFi provisioning mode..."

# Remove ethernet connection status
sudo rm -f /etc/nipux/active-ethernet
sudo rm -f /etc/nipux/network-status

# Disconnect WiFi to force provisioning
sudo nmcli device disconnect $(nmcli -t -f DEVICE,TYPE dev | grep wifi | cut -d: -f1) 2>/dev/null || true

# Stop and restart ethernet monitor (will detect no connection and start WiFi provisioning)
sudo systemctl restart nipux-ethernet-monitor

echo "✓ Reset complete. System should start WiFi provisioning mode."
echo "Look for access point: $(hostname)-setup"
echo "Monitor status with: ./status.sh"
EOF
    chmod +x "$SCRIPT_DIR/reset.sh"
    
    log_success "Helper scripts created"
}

# Final verification
verify_installation() {
    log_info "Verifying installation..."
    
    local errors=0
    
    # Check for essential services
    if [[ ! -f "/etc/systemd/system/wifi-provisioning.service" ]]; then
        log_warning "Main provisioning service not found"
        ((errors++))
    fi
    
    # Check for web interface
    if [[ ! -f "/var/www/wifi-setup/index.html" ]]; then
        log_warning "Web interface not found"
        ((errors++))
    fi
    
    # Check for configuration
    if [[ ! -d "/etc/wifi-provisioning" ]]; then
        log_warning "Configuration directory not found"
        ((errors++))
    fi
    
    if [[ $errors -eq 0 ]]; then
        log_success "Installation verification passed!"
        return 0
    else
        log_warning "Installation verification found $errors issues, but system may still work"
        return 0  # Don't fail completely
    fi
}

# Display final instructions
show_final_instructions() {
    local hostname=$(hostname)
    
    cat << EOF

${GREEN}🎉 NiPux Ethernet-First Network Management Setup Complete!${NC}

${BLUE}How it works:${NC}
1. ${YELLOW}System monitors ethernet connection continuously${NC}
2. If ethernet is connected: Uses ethernet, WiFi provisioning stays inactive
3. If ethernet disconnected: Automatically starts WiFi provisioning mode
4. WiFi provisioning creates: ${YELLOW}${hostname}-setup${NC} access point
5. After WiFi setup: Connects to WiFi and stops access point

${BLUE}What happens on reboot:${NC}
• System checks for ethernet connection first
• If ethernet available: Normal operation with ethernet
• If no ethernet: Starts WiFi provisioning automatically

${BLUE}Useful commands:${NC}
• Check status:       ${YELLOW}$SCRIPT_DIR/status.sh${NC}
• Force WiFi setup:   ${YELLOW}$SCRIPT_DIR/reset.sh${NC}
• View monitor logs:  ${YELLOW}sudo journalctl -u nipux-ethernet-monitor -f${NC}
• View WiFi logs:     ${YELLOW}sudo journalctl -u wifi-provisioning -f${NC}

${BLUE}Troubleshooting:${NC}
• WiFi setup IP:      ${YELLOW}192.168.4.1${NC}
• Config directory:   ${YELLOW}/etc/nipux${NC}
• WiFi interface:     ${YELLOW}/var/www/wifi-setup${NC}
• Monitor status:     ${YELLOW}sudo /usr/local/bin/nipux-ethernet-monitor status${NC}

${GREEN}🚀 Ready to use! Reboot now to activate the ethernet monitoring system.${NC}

EOF
}

# Main installation function
main() {
    show_banner
    echo
    log_info "Starting unified NiPux setup..."
    echo
    
    # Pre-flight checks
    check_permissions
    detect_system
    
    echo
    log_info "Beginning installation process..."
    
    # Core installation steps
    install_dependencies
    setup_ethernet_monitoring
    setup_wifi_provisioning
    fix_permissions
    enable_services
    create_helper_scripts
    verify_installation
    
    echo
    show_final_instructions
    
    # Ask about reboot
    echo
    read -p "Would you like to reboot now to activate the WiFi provisioning system? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "Rebooting system in 3 seconds..."
        sleep 3
        $SUDO_CMD reboot
    else
        log_info "Please reboot manually when ready to activate the system"
        echo "Command: ${YELLOW}sudo reboot${NC}"
    fi
}

# Handle errors gracefully
handle_error() {
    local line_no=$1
    local error_code=$2
    echo
    log_error "Setup failed on line $line_no with exit code $error_code"
    log_info "Check the output above for details"
    echo
    log_info "You can try running individual setup scripts manually:"
    log_info "• $SCRIPT_DIR/install-dependencies.sh"
    log_info "• $SCRIPT_DIR/setup-wifi-provisioning.sh"
    exit "$error_code"
}

trap 'handle_error ${LINENO} $?' ERR

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi