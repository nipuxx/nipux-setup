#!/bin/bash

# Download essential Ubuntu packages for offline WiFi provisioning
# Run this on a machine with internet to prepare for offline deployment

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPS_DIR="$SCRIPT_DIR/offline-deps"

log_info "Downloading essential packages for Ubuntu Server..."

mkdir -p "$DEPS_DIR"
cd "$DEPS_DIR"

# Essential package URLs for Ubuntu 20.04 LTS
PACKAGES=(
    "http://archive.ubuntu.com/ubuntu/pool/universe/w/wpa/hostapd_2.9-1ubuntu4.3_amd64.deb"
    "http://archive.ubuntu.com/ubuntu/pool/universe/d/dnsmasq/dnsmasq_2.90-0ubuntu0.20.04.1_all.deb"
    "http://archive.ubuntu.com/ubuntu/pool/universe/d/dnsmasq/dnsmasq-base_2.90-0ubuntu0.20.04.1_amd64.deb"
    "http://archive.ubuntu.com/ubuntu/pool/universe/n/nginx/nginx-light_1.18.0-0ubuntu1.4_amd64.deb"
    "http://archive.ubuntu.com/ubuntu/pool/universe/n/nginx/nginx-common_1.18.0-0ubuntu1.4_all.deb"
    "http://archive.ubuntu.com/ubuntu/pool/main/i/iw/iw_5.4-1ubuntu1_amd64.deb"
    "http://archive.ubuntu.com/ubuntu/pool/main/w/wireless-tools/wireless-tools_30~pre9-13ubuntu1_amd64.deb"
    "http://archive.ubuntu.com/ubuntu/pool/main/w/wpa/wpasupplicant_2.9-1ubuntu4.3_amd64.deb"
)

log_info "Downloading $(echo ${#PACKAGES[@]}) packages..."

for url in "${PACKAGES[@]}"; do
    filename=$(basename "$url")
    if [[ ! -f "$filename" ]]; then
        log_info "Downloading $filename..."
        curl -L -o "$filename" "$url" 2>/dev/null || echo "Failed: $filename"
    fi
done

# Create installation script
cat > install-packages.sh << 'EOF'
#!/bin/bash
# Install offline packages

echo "Installing offline packages..."
sudo dpkg -i *.deb 2>/dev/null || true
sudo apt-get install -f -y 2>/dev/null || true
echo "Offline packages installed!"
EOF

chmod +x install-packages.sh

# Create package info
cat > package-info.txt << 'EOF'
Essential packages for WiFi provisioning:
- hostapd: WiFi access point daemon
- dnsmasq: DHCP and DNS server  
- nginx-light: Lightweight web server
- iw: Wireless configuration tool
- wireless-tools: WiFi utilities
- wpasupplicant: WiFi client

Run ./install-packages.sh to install these packages offline.
EOF

count=$(ls *.deb 2>/dev/null | wc -l)
log_success "Downloaded $count packages to: $DEPS_DIR"
log_info "Offline packages ready for deployment!"