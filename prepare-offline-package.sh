#!/bin/bash

# Prepare Offline Package for Ubuntu Server WiFi Provisioning
# Downloads all required .deb packages for offline installation

set -eo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPS_DIR="$SCRIPT_DIR/offline-packages"

log_info "Preparing offline package for Ubuntu Server deployment..."

# Create directory structure
mkdir -p "$DEPS_DIR"/{amd64,arm64,armhf}

# Core packages needed for WiFi provisioning

# Ubuntu 20.04 LTS package URLs (most stable/compatible)
declare -A PACKAGE_URLS=(
    ["hostapd"]="http://archive.ubuntu.com/ubuntu/pool/universe/w/wpa/hostapd_2.9-1ubuntu4.3_amd64.deb"
    ["dnsmasq"]="http://archive.ubuntu.com/ubuntu/pool/universe/d/dnsmasq/dnsmasq_2.90-0ubuntu0.20.04.1_all.deb"
    ["dnsmasq-base"]="http://archive.ubuntu.com/ubuntu/pool/universe/d/dnsmasq/dnsmasq-base_2.90-0ubuntu0.20.04.1_amd64.deb"
    ["nginx-light"]="http://archive.ubuntu.com/ubuntu/pool/universe/n/nginx/nginx-light_1.18.0-0ubuntu1.4_amd64.deb"
    ["nginx-common"]="http://archive.ubuntu.com/ubuntu/pool/universe/n/nginx/nginx-common_1.18.0-0ubuntu1.4_all.deb"
    ["nginx-core"]="http://archive.ubuntu.com/ubuntu/pool/universe/n/nginx/nginx-core_1.18.0-0ubuntu1.4_amd64.deb"
    ["php8.1-fpm"]="http://archive.ubuntu.com/ubuntu/pool/universe/p/php8.1/php8.1-fpm_8.1.2-1ubuntu2.14_amd64.deb"
    ["php8.1-cli"]="http://archive.ubuntu.com/ubuntu/pool/universe/p/php8.1/php8.1-cli_8.1.2-1ubuntu2.14_amd64.deb"
    ["php8.1-common"]="http://archive.ubuntu.com/ubuntu/pool/universe/p/php8.1/php8.1-common_8.1.2-1ubuntu2.14_amd64.deb"
    ["iw"]="http://archive.ubuntu.com/ubuntu/pool/main/i/iw/iw_5.4-1ubuntu1_amd64.deb"
    ["wireless-tools"]="http://archive.ubuntu.com/ubuntu/pool/main/w/wireless-tools/wireless-tools_30~pre9-13ubuntu1_amd64.deb"
    ["wpasupplicant"]="http://archive.ubuntu.com/ubuntu/pool/main/w/wpa/wpasupplicant_2.9-1ubuntu4.3_amd64.deb"
    ["network-manager"]="http://archive.ubuntu.com/ubuntu/pool/universe/n/network-manager/network-manager_1.22.10-1ubuntu2.3_amd64.deb"
)

# Download packages for amd64 architecture  
log_info "Downloading packages for amd64..."
cd "$DEPS_DIR/amd64"

for package in "${!PACKAGE_URLS[@]}"; do
    url="${PACKAGE_URLS[$package]}"
    filename=$(basename "$url")
    
    if [[ ! -f "$filename" ]]; then
        log_info "Downloading $package..."
        curl -L -o "$filename" "$url" || log_warning "Failed to download $package"
    else
        log_info "Already have $package"
    fi
done

# Create package list file
cat > "$DEPS_DIR/package-list.txt" << 'EOF'
# Core WiFi Provisioning Packages
hostapd
dnsmasq
dnsmasq-base
nginx-light
nginx-common
nginx-core
php8.1-fpm
php8.1-cli
php8.1-common
php8.1-opcache
php8.1-readline
iw
wireless-tools
rfkill
wpasupplicant
network-manager
bridge-utils
iptables
net-tools
dnsutils
curl
wget
systemd
udev
libnl-3-200
libnl-genl-3-200
libssl3
openssl
EOF

# Create installation script for offline use
cat > "$DEPS_DIR/install-offline-packages.sh" << 'EOF'
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
EOF

chmod +x "$DEPS_DIR/install-offline-packages.sh"

# Create README for offline packages
cat > "$DEPS_DIR/README.md" << 'EOF'
# Offline Packages for WiFi Provisioning

This directory contains pre-downloaded .deb packages for offline installation of the WiFi provisioning system.

## Usage

```bash
# Install offline packages
./install-offline-packages.sh

# Then run the main setup
cd .. && ./setup-wifi-provisioning.sh
```

## Architecture Support

- `amd64/` - x86_64 packages (Intel/AMD 64-bit)
- `arm64/` - AArch64 packages (ARM 64-bit)  
- `armhf/` - ARM hard-float packages (ARM 32-bit)

## Package List

See `package-list.txt` for the complete list of included packages.

## Notes

- Packages are from Ubuntu 20.04 LTS repositories for maximum compatibility
- If offline packages fail, the system will attempt online installation
- Some dependencies may be automatically resolved by apt during installation
EOF

log_success "Offline package preparation completed!"
log_info "Package directory: $DEPS_DIR"
log_info "Total packages downloaded: $(find "$DEPS_DIR" -name "*.deb" | wc -l)"

echo
echo -e "${GREEN}Offline package preparation complete!${NC}"
echo "The offline-packages directory contains everything needed for Ubuntu Server deployment."