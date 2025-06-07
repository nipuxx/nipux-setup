#!/bin/bash
# Offline package installer for Ubuntu Server

set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Detect architecture
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

PACKAGE_DIR="$SCRIPT_DIR/$DEB_ARCH"

log_info "Installing offline packages for $ARCH ($DEB_ARCH)..."

if [[ ! -d "$PACKAGE_DIR" ]]; then
    log_error "Package directory not found: $PACKAGE_DIR"
    exit 1
fi

cd "$PACKAGE_DIR"

# Install all .deb packages
if ls *.deb >/dev/null 2>&1; then
    log_info "Installing .deb packages..."
    sudo dpkg -i *.deb 2>/dev/null || true
    
    # Fix any dependency issues
    log_info "Fixing dependencies..."
    sudo apt-get install -f -y 2>/dev/null || true
    
    log_success "Offline packages installed successfully"
else
    log_warning "No .deb packages found in $PACKAGE_DIR"
fi

# Verify key packages are installed
log_info "Verifying installation..."
REQUIRED_PACKAGES=("hostapd" "dnsmasq" "nginx" "php-fpm" "iw" "wpasupplicant" "network-manager")

missing_packages=()
for package in "${REQUIRED_PACKAGES[@]}"; do
    if dpkg -l | grep -q "^ii  $package"; then
        log_success "$package is installed"
    else
        log_warning "$package is missing"
        missing_packages+=("$package")
    fi
done

if [[ ${#missing_packages[@]} -eq 0 ]]; then
    log_success "All required packages are installed!"
else
    log_warning "Missing packages: ${missing_packages[*]}"
    log_info "Attempting to install from system repositories..."
    sudo apt-get update -qq 2>/dev/null || true
    sudo apt-get install -y "${missing_packages[@]}" || log_warning "Some packages could not be installed"
fi
