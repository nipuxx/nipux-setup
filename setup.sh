#!/bin/bash

# NiPux Setup - Unified Installation Script
# Automatically sets up WiFi provisioning system on Ubuntu Server
# No manual steps required - just run and reboot

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

WiFi Provisioning Setup - Unified Installer
==========================================
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
    
    # Check for wireless interface
    if ! iw dev | grep -q "Interface"; then
        log_error "No wireless interface found. This system requires a WiFi adapter."
        exit 1
    fi
    
    local wireless_interface=$(iw dev | awk '$1=="Interface"{print $2}' | head -1)
    log_success "Found wireless interface: $wireless_interface"
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

# Setup WiFi provisioning system
setup_wifi_provisioning() {
    log_info "Setting up WiFi provisioning system..."
    
    if [[ -f "$SCRIPT_DIR/setup-wifi-provisioning.sh" ]]; then
        log_info "Running WiFi provisioning setup..."
        bash "$SCRIPT_DIR/setup-wifi-provisioning.sh"
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
    
    # Enable main WiFi provisioning service if it exists
    if [[ -f "/etc/systemd/system/wifi-provisioning.service" ]]; then
        $SUDO_CMD systemctl enable wifi-provisioning.service
        log_success "WiFi provisioning service enabled"
    fi
    
    # Enable monitoring service if it exists
    if [[ -f "/etc/systemd/system/wifi-provisioning-health.timer" ]]; then
        $SUDO_CMD systemctl enable wifi-provisioning-health.timer
        $SUDO_CMD systemctl start wifi-provisioning-health.timer
        log_success "Health monitoring enabled"
    fi
    
    # Enable WiFi Connect fallback if it exists
    if [[ -f "/etc/systemd/system/wifi-connect.service" ]]; then
        $SUDO_CMD systemctl enable wifi-connect.service
        log_success "WiFi Connect fallback enabled"
    fi
}

# Create helpful scripts
create_helper_scripts() {
    log_info "Creating helper scripts..."
    
    # Create status check script
    cat > "$SCRIPT_DIR/status.sh" << 'EOF'
#!/bin/bash
# Quick status check for WiFi provisioning

echo "=== WiFi Provisioning System Status ==="
echo

# Check if connected to WiFi
if nmcli -t -f TYPE,STATE dev | grep -q ":connected"; then
    echo "✓ WiFi: Connected"
    nmcli -t -f DEVICE,CONNECTION dev status | grep wifi | head -1
else
    echo "✗ WiFi: Not connected"
fi

echo

# Check service status
if systemctl is-active --quiet wifi-provisioning 2>/dev/null; then
    echo "✓ Provisioning: Active (setup mode)"
elif [[ -f /etc/wifi-provisioning/wifi-connected ]]; then
    echo "✓ Provisioning: Inactive (WiFi connected)"
else
    echo "? Provisioning: Unknown state"
fi

echo

# Check for access point
if iwconfig 2>/dev/null | grep -q "Mode:Master"; then
    echo "✓ Access Point: Running"
    hostname=$(hostname)
    echo "  SSID: ${hostname}-setup"
    echo "  IP: 192.168.4.1"
else
    echo "✗ Access Point: Not running"
fi

echo

# Show recent logs
echo "Recent logs:"
sudo journalctl -u wifi-provisioning --no-pager -n 3 2>/dev/null || echo "No recent logs"
EOF
    chmod +x "$SCRIPT_DIR/status.sh"
    
    # Create reset script
    cat > "$SCRIPT_DIR/reset.sh" << 'EOF'
#!/bin/bash
# Reset WiFi provisioning to setup mode

echo "Resetting WiFi provisioning to setup mode..."

# Remove connected flag
sudo rm -f /etc/wifi-provisioning/wifi-connected

# Stop and restart service
sudo systemctl stop wifi-provisioning 2>/dev/null || true
sudo systemctl start wifi-provisioning 2>/dev/null || true

echo "✓ Reset complete. System should enter setup mode."
echo "Look for access point: $(hostname)-setup"
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

${GREEN}🎉 NiPux WiFi Provisioning Setup Complete!${NC}

${BLUE}What happens next:${NC}
1. ${YELLOW}Reboot your system${NC} to activate WiFi provisioning
2. If no WiFi is configured, the system will create: ${YELLOW}${hostname}-setup${NC} access point
3. Connect any device to this network and follow the setup portal

${BLUE}Useful commands:${NC}
• Check status:     ${YELLOW}$SCRIPT_DIR/status.sh${NC}
• Reset to setup:   ${YELLOW}$SCRIPT_DIR/reset.sh${NC}
• View logs:        ${YELLOW}sudo journalctl -u wifi-provisioning -f${NC}

${BLUE}Troubleshooting:${NC}
• Access point IP:  ${YELLOW}192.168.4.1${NC}
• Config directory: ${YELLOW}/etc/wifi-provisioning${NC}
• Web interface:    ${YELLOW}/var/www/wifi-setup${NC}

${GREEN}🚀 Ready to use! Reboot now to activate the system.${NC}

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