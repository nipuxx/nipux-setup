#!/bin/bash

# Offline WiFi Setup Dependencies Installer
# This script installs all required packages and dependencies for the WiFi setup system
# Designed to work offline with bundled .deb packages

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
DEPS_DIR="$SCRIPT_DIR/dependencies"

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        log_error "This script should not be run as root. Use sudo when needed."
        exit 1
    fi
}

# Detect OS and architecture
detect_system() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
        
        case "$OS" in
            ubuntu|debian)
                log_info "Detected OS: $OS $OS_VERSION"
                ;;
            *)
                log_error "Unsupported OS: $OS. This script supports Ubuntu/Debian only."
                exit 1
                ;;
        esac
    else
        log_error "Cannot detect OS"
        exit 1
    fi
    
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64) DEB_ARCH="amd64" ;;
        armv7l) DEB_ARCH="armhf" ;;
        aarch64) DEB_ARCH="arm64" ;;
        *) 
            log_error "Unsupported architecture: $ARCH"
            exit 1
            ;;
    esac
    
    log_info "Architecture: $ARCH ($DEB_ARCH)"
}

# Create dependencies directory structure
create_deps_structure() {
    log_info "Creating dependencies directory structure..."
    
    mkdir -p "$DEPS_DIR"/{debs,configs,scripts}
    
    # Create package list for offline download
    cat > "$DEPS_DIR/required-packages.txt" << 'EOF'
hostapd
dnsmasq
nginx-light
php-fpm
php-cli
iw
wireless-tools
rfkill
wpasupplicant
network-manager
systemd
udev
bridge-utils
iptables
net-tools
EOF
    
    log_success "Dependencies structure created"
}

# Install packages from local debs or system
install_packages() {
    log_info "Installing required packages..."
    
    local packages=(
        "hostapd"
        "dnsmasq" 
        "nginx-light"
        "php-fpm"
        "php-cli"
        "iw"
        "wireless-tools"
        "rfkill"
        "wpasupplicant"
        "network-manager"
        "bridge-utils"
        "iptables"
        "net-tools"
    )
    
    # Try to install from local debs first
    if [[ -d "$DEPS_DIR/debs" ]] && [[ -n "$(ls -A "$DEPS_DIR/debs" 2>/dev/null)" ]]; then
        log_info "Installing from local packages..."
        sudo dpkg -i "$DEPS_DIR/debs"/*.deb 2>/dev/null || true
        sudo apt-get install -f -y 2>/dev/null || true
    fi
    
    # Install any missing packages from system
    local missing_packages=()
    for package in "${packages[@]}"; do
        if ! dpkg -l | grep -q "^ii  $package "; then
            missing_packages+=("$package")
        fi
    done
    
    if [[ ${#missing_packages[@]} -gt 0 ]]; then
        log_info "Installing missing packages: ${missing_packages[*]}"
        sudo apt-get update -qq 2>/dev/null || log_warning "Could not update package list"
        sudo apt-get install -y "${missing_packages[@]}" || {
            log_error "Failed to install some packages. Offline mode may not work correctly."
        }
    fi
    
    log_success "Package installation completed"
}

# Create offline package download script
create_download_script() {
    log_info "Creating offline package download script..."
    
    cat > "$DEPS_DIR/download-packages.sh" << 'EOF'
#!/bin/bash
# Script to download all required packages for offline installation
# Run this on a machine with internet access

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPS_DIR="$SCRIPT_DIR"

log_info() { echo -e "\033[0;34m[INFO]\033[0m $1"; }
log_success() { echo -e "\033[0;32m[SUCCESS]\033[0m $1"; }

# Create download directory
mkdir -p "$DEPS_DIR/debs"
cd "$DEPS_DIR/debs"

# Read package list
if [[ ! -f "$DEPS_DIR/required-packages.txt" ]]; then
    echo "required-packages.txt not found!"
    exit 1
fi

log_info "Downloading packages..."

# Download packages and dependencies
apt-get download $(cat "$DEPS_DIR/required-packages.txt" | tr '\n' ' ')

# Download dependencies
for package in $(cat "$DEPS_DIR/required-packages.txt"); do
    apt-cache depends "$package" | grep "Depends:" | cut -d: -f2 | tr -d ' ' | while read dep; do
        apt-get download "$dep" 2>/dev/null || true
    done
done

log_success "Packages downloaded to: $DEPS_DIR/debs"
log_info "Total packages: $(ls *.deb | wc -l)"
EOF
    
    chmod +x "$DEPS_DIR/download-packages.sh"
    log_success "Download script created: $DEPS_DIR/download-packages.sh"
}

# Main installation
main() {
    log_info "Starting dependencies installation..."
    
    check_root
    detect_system
    create_deps_structure
    install_packages
    create_download_script
    
    log_success "Dependencies installation completed!"
    
    cat << EOF

${GREEN}Next Steps:${NC}
1. If you need offline capability, run: ${YELLOW}$DEPS_DIR/download-packages.sh${NC}
2. Copy the entire project to your target device
3. Run the main setup script: ${YELLOW}./setup-wifi-provisioning.sh${NC}

EOF
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi