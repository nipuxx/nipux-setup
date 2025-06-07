#!/bin/bash

# WiFi Connect Setup Script
# This script automates the installation and configuration of balena wifi-connect
# for a plug-and-play WiFi provisioning solution

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        log_info "Running as root - will handle permissions appropriately"
        SUDO_CMD=""
    else
        log_info "Running as user - will use sudo when needed"
        SUDO_CMD="sudo"
    fi
}

# Check if sudo is available
check_sudo() {
    if ! command -v sudo &> /dev/null; then
        log_error "sudo is required but not installed. Please install sudo first."
        exit 1
    fi
    
    # Test sudo access
    if ! sudo -n true 2>/dev/null; then
        log_info "This script requires sudo access. You may be prompted for your password."
        sudo -v || {
            log_error "Failed to obtain sudo access"
            exit 1
        }
    fi
}

# Detect OS and package manager
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    else
        log_error "Cannot detect OS. This script supports Ubuntu/Debian systems."
        exit 1
    fi
    
    case $OS in
        ubuntu|debian)
            PACKAGE_MANAGER="apt"
            ;;
        *)
            log_error "Unsupported OS: $OS. This script supports Ubuntu/Debian."
            exit 1
            ;;
    esac
    
    log_info "Detected OS: $OS $OS_VERSION"
}

# Check network connectivity
check_network() {
    log_info "Checking network connectivity..."
    if ! ping -c 1 google.com &> /dev/null; then
        log_warning "No internet connectivity detected. Please ensure you have internet access."
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Install required packages
install_packages() {
    log_info "Updating package list..."
    sudo apt update || {
        log_error "Failed to update package list"
        exit 1
    }
    
    log_info "Installing required packages: network-manager dnsmasq-base..."
    sudo apt install -y network-manager dnsmasq-base curl tar || {
        log_error "Failed to install required packages"
        exit 1
    }
    
    log_success "Required packages installed successfully"
}

# Download and install wifi-connect binary
install_wifi_connect() {
    local version="5.0.3"
    local url="https://github.com/balena-os/wifi-connect/releases/download/v${version}/wifi-connect-${version}-linux-x64.tar.gz"
    local temp_dir="/tmp/wifi-connect-install"
    
    log_info "Downloading wifi-connect v${version}..."
    
    # Create temporary directory
    mkdir -p "$temp_dir"
    cd "$temp_dir"
    
    # Download and extract
    curl -L "$url" | tar xz || {
        log_error "Failed to download and extract wifi-connect"
        exit 1
    }
    
    # Install binary
    sudo mv wifi-connect /usr/local/bin/ || {
        log_error "Failed to install wifi-connect binary"
        exit 1
    }
    
    # Set permissions
    sudo chmod +x /usr/local/bin/wifi-connect
    
    # Cleanup
    cd - > /dev/null
    rm -rf "$temp_dir"
    
    # Verify installation
    if /usr/local/bin/wifi-connect --version &> /dev/null; then
        log_success "wifi-connect v${version} installed successfully"
    else
        log_error "wifi-connect installation verification failed"
        exit 1
    fi
}

# Create systemd service
create_systemd_service() {
    log_info "Creating systemd service..."
    
    # Get hostname for SSID
    local hostname=$(hostname)
    
    sudo tee /etc/systemd/system/wifi-connect.service > /dev/null << EOF
[Unit]
Description=WiFi Setup Hotspot
After=network.target NetworkManager.service
Wants=NetworkManager.service
ConditionPathExists=!/var/run/wifi-connected

[Service]
Type=simple
Environment="PORTAL_SSID=${hostname}-setup"
ExecStart=/usr/local/bin/wifi-connect --portal-ssid ${hostname}-setup
ExecStartPost=/bin/touch /var/run/wifi-connected
Restart=on-failure
RestartSec=5
User=root

[Install]
WantedBy=multi-user.target
EOF

    log_success "Systemd service created at /etc/systemd/system/wifi-connect.service"
}

# Create cleanup script for removing wifi-connected flag
create_cleanup_script() {
    log_info "Creating network cleanup script..."
    
    sudo tee /usr/local/bin/wifi-connect-cleanup > /dev/null << 'EOF'
#!/bin/bash
# Remove wifi-connected flag when network is down
# This allows wifi-connect to start again if connection is lost

CONNECTED_FLAG="/var/run/wifi-connected"

# Check if NetworkManager reports any active connections
if ! nmcli -t -f TYPE,STATE dev | grep -q ":connected"; then
    if [[ -f "$CONNECTED_FLAG" ]]; then
        rm -f "$CONNECTED_FLAG"
        logger "WiFi connection lost, removed wifi-connected flag"
    fi
fi
EOF

    sudo chmod +x /usr/local/bin/wifi-connect-cleanup
    
    log_success "Cleanup script created at /usr/local/bin/wifi-connect-cleanup"
}

# Create NetworkManager dispatcher script
create_nm_dispatcher() {
    log_info "Creating NetworkManager dispatcher script..."
    
    sudo tee /etc/NetworkManager/dispatcher.d/99-wifi-connect > /dev/null << 'EOF'
#!/bin/bash
# NetworkManager dispatcher script for wifi-connect
# Removes the wifi-connected flag when network goes down

interface=$1
status=$2

case $status in
    down)
        if [[ "$interface" == wl* ]] || [[ "$interface" == wlan* ]]; then
            /usr/local/bin/wifi-connect-cleanup
        fi
        ;;
esac
EOF

    sudo chmod +x /etc/NetworkManager/dispatcher.d/99-wifi-connect
    
    log_success "NetworkManager dispatcher script created"
}

# Configure NetworkManager
configure_networkmanager() {
    log_info "Configuring NetworkManager..."
    
    # Ensure NetworkManager is enabled and started
    sudo systemctl enable NetworkManager
    sudo systemctl start NetworkManager
    
    # Wait for NetworkManager to be ready
    sleep 2
    
    log_success "NetworkManager configured and started"
}

# Enable and configure the service
enable_service() {
    log_info "Enabling wifi-connect service..."
    
    # Reload systemd
    sudo systemctl daemon-reload
    
    # Enable the service
    sudo systemctl enable wifi-connect.service
    
    log_success "wifi-connect service enabled"
}

# Create uninstall script
create_uninstall_script() {
    log_info "Creating uninstall script..."
    
    tee uninstall-wifi-connect.sh > /dev/null << 'EOF'
#!/bin/bash
# Uninstall script for wifi-connect

echo "Uninstalling wifi-connect..."

# Stop and disable service
sudo systemctl stop wifi-connect.service 2>/dev/null || true
sudo systemctl disable wifi-connect.service 2>/dev/null || true

# Remove files
sudo rm -f /etc/systemd/system/wifi-connect.service
sudo rm -f /usr/local/bin/wifi-connect
sudo rm -f /usr/local/bin/wifi-connect-cleanup
sudo rm -f /etc/NetworkManager/dispatcher.d/99-wifi-connect
sudo rm -f /var/run/wifi-connected

# Reload systemd
sudo systemctl daemon-reload

echo "wifi-connect uninstalled successfully"
EOF

    chmod +x uninstall-wifi-connect.sh
    
    log_success "Uninstall script created: ./uninstall-wifi-connect.sh"
}

# Verification function
verify_installation() {
    log_info "Verifying installation..."
    
    local errors=0
    
    # Check binary
    if [[ ! -x /usr/local/bin/wifi-connect ]]; then
        log_error "wifi-connect binary not found or not executable"
        ((errors++))
    fi
    
    # Check service file
    if [[ ! -f /etc/systemd/system/wifi-connect.service ]]; then
        log_error "systemd service file not found"
        ((errors++))
    fi
    
    # Check if service is enabled
    if ! systemctl is-enabled wifi-connect.service &> /dev/null; then
        log_error "wifi-connect service is not enabled"
        ((errors++))
    fi
    
    # Check NetworkManager
    if ! systemctl is-active NetworkManager &> /dev/null; then
        log_warning "NetworkManager is not running"
    fi
    
    if [[ $errors -eq 0 ]]; then
        log_success "Installation verification passed!"
        return 0
    else
        log_error "Installation verification failed with $errors errors"
        return 1
    fi
}

# Display usage information
show_usage() {
    local hostname=$(hostname)
    cat << EOF

${GREEN}WiFi Connect Setup Complete!${NC}

${BLUE}How it works:${NC}
1. When your device has no WiFi connection, it will automatically create a hotspot
2. The hotspot SSID will be: ${YELLOW}${hostname}-setup${NC}
3. Connect to this hotspot with any device (phone, laptop, etc.)
4. A captive portal will appear where you can select your WiFi network and enter the password
5. Once configured, the device will connect to your WiFi and the hotspot will disappear

${BLUE}Manual Controls:${NC}
• Start service: ${YELLOW}sudo systemctl start wifi-connect${NC}
• Stop service:  ${YELLOW}sudo systemctl stop wifi-connect${NC}
• Check status:  ${YELLOW}sudo systemctl status wifi-connect${NC}
• View logs:     ${YELLOW}sudo journalctl -u wifi-connect -f${NC}

${BLUE}Uninstall:${NC}
• Run: ${YELLOW}./uninstall-wifi-connect.sh${NC}

${GREEN}Reboot now to activate the WiFi provisioning system!${NC}

EOF
}

# Main installation function
main() {
    log_info "Starting WiFi Connect setup..."
    
    # Pre-flight checks
    check_root
    check_sudo
    detect_os
    check_network
    
    # Installation steps
    install_packages
    install_wifi_connect
    configure_networkmanager
    create_systemd_service
    create_cleanup_script
    create_nm_dispatcher
    enable_service
    create_uninstall_script
    
    # Verification
    if verify_installation; then
        show_usage
        
        echo
        read -p "Would you like to reboot now to activate the service? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Rebooting system..."
            sudo reboot
        else
            log_info "Please reboot manually when ready: sudo reboot"
        fi
    else
        log_error "Installation completed with errors. Please check the logs above."
        exit 1
    fi
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi 