#!/bin/bash

# Production-Grade Offline WiFi Provisioning System
# Creates an access point for WiFi configuration without internet dependency
# Designed for Ubuntu Server deployment via USB

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/var/log/wifi-provisioning.log"
CONFIG_DIR="/etc/wifi-provisioning"
WEB_DIR="/var/www/wifi-setup"
AP_SSID="${HOSTNAME:-$(hostname)}-setup"
AP_PASSPHRASE=""  # Open network for easy access
AP_CHANNEL="6"
AP_IP="192.168.4.1"
AP_SUBNET="192.168.4.0/24"
AP_INTERFACE="wlan0"
DHCP_RANGE_START="192.168.4.10"
DHCP_RANGE_END="192.168.4.50"

# Logging functions
log_info() { 
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOG_FILE" 2>/dev/null || echo -e "${BLUE}[INFO]${NC} $1"
}
log_success() { 
    echo -e "${GREEN}[SUCCESS]${NC} $1" | tee -a "$LOG_FILE" 2>/dev/null || echo -e "${GREEN}[SUCCESS]${NC} $1"
}
log_warning() { 
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOG_FILE" 2>/dev/null || echo -e "${YELLOW}[WARNING]${NC} $1"
}
log_error() { 
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOG_FILE" 2>/dev/null || echo -e "${RED}[ERROR]${NC} $1"
}

# Error handling
handle_error() {
    local line_no=$1
    local error_code=$2
    log_error "Error on line $line_no: exit code $error_code"
    cleanup_on_failure
    exit "$error_code"
}

trap 'handle_error ${LINENO} $?' ERR

# Cleanup on failure
cleanup_on_failure() {
    log_warning "Cleaning up due to failure..."
    sudo systemctl stop hostapd 2>/dev/null || true
    sudo systemctl stop dnsmasq 2>/dev/null || true
    sudo systemctl stop nginx 2>/dev/null || true
    sudo systemctl stop php*-fpm 2>/dev/null || true
    sudo ip link set "$AP_INTERFACE" down 2>/dev/null || true
}

# Pre-flight checks
check_requirements() {
    log_info "Performing pre-flight checks..."
    
    # Root check
    if [[ $EUID -eq 0 ]]; then
        log_error "Do not run as root. Use sudo when needed."
        exit 1
    fi
    
    # Sudo check
    if ! sudo -n true 2>/dev/null; then
        log_info "Need sudo access for system configuration"
        sudo -v || exit 1
    fi
    
    # OS check
    if [[ ! -f /etc/os-release ]]; then
        log_error "Cannot detect OS"
        exit 1
    fi
    
    . /etc/os-release
    if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
        log_error "Unsupported OS: $ID"
        exit 1
    fi
    
    # Check for wireless interface
    if ! iw dev | grep -q "Interface"; then
        log_error "No wireless interface found"
        exit 1
    fi
    
    # Find the wireless interface
    AP_INTERFACE=$(iw dev | awk '$1=="Interface"{print $2}' | head -1)
    if [[ -z "$AP_INTERFACE" ]]; then
        log_error "Could not determine wireless interface"
        exit 1
    fi
    
    log_success "Pre-flight checks passed. Using interface: $AP_INTERFACE"
}

# Install dependencies
install_dependencies() {
    log_info "Installing dependencies..."
    
    # Try to run the dependencies installer first
    if [[ -f "$SCRIPT_DIR/install-dependencies.sh" ]]; then
        bash "$SCRIPT_DIR/install-dependencies.sh"
    else
        # Fallback to manual installation
        local packages=(
            "hostapd" "dnsmasq" "nginx-light" "php-fpm" "php-cli"
            "iw" "wireless-tools" "rfkill" "wpasupplicant" 
            "network-manager" "bridge-utils" "iptables"
        )
        
        sudo apt-get update -qq || log_warning "Could not update package list"
        for package in "${packages[@]}"; do
            if ! dpkg -l | grep -q "^ii  $package "; then
                sudo apt-get install -y "$package" || log_warning "Failed to install $package"
            fi
        done
    fi
    
    log_success "Dependencies installation completed"
}

# Create directory structure
create_directories() {
    log_info "Creating directory structure..."
    
    sudo mkdir -p "$CONFIG_DIR"/{configs,scripts,logs}
    sudo mkdir -p "$WEB_DIR"/{css,js,api}
    sudo mkdir -p /var/log/wifi-provisioning
    
    # Set permissions
    sudo chown -R www-data:www-data "$WEB_DIR"
    sudo chmod -R 755 "$WEB_DIR"
    
    log_success "Directory structure created"
}

# Configure hostapd
configure_hostapd() {
    log_info "Configuring hostapd..."
    
    sudo tee "$CONFIG_DIR/hostapd.conf" > /dev/null << EOF
# WiFi Provisioning Access Point Configuration
interface=$AP_INTERFACE
driver=nl80211
ssid=$AP_SSID
hw_mode=g
channel=$AP_CHANNEL
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=0
EOF

    # Create hostapd service override
    sudo mkdir -p /etc/systemd/system/hostapd.service.d
    sudo tee /etc/systemd/system/hostapd.service.d/override.conf > /dev/null << EOF
[Unit]
After=network.target
ConditionPathExists=!$CONFIG_DIR/wifi-connected

[Service]
ExecStart=
ExecStart=/usr/sbin/hostapd $CONFIG_DIR/hostapd.conf
Restart=on-failure
RestartSec=5
EOF

    log_success "hostapd configured"
}

# Configure dnsmasq
configure_dnsmasq() {
    log_info "Configuring dnsmasq..."
    
    sudo tee "$CONFIG_DIR/dnsmasq.conf" > /dev/null << EOF
# WiFi Provisioning DHCP and DNS Configuration
interface=$AP_INTERFACE
bind-interfaces
server=8.8.8.8
server=8.8.4.4
domain-needed
bogus-priv
dhcp-range=$DHCP_RANGE_START,$DHCP_RANGE_END,255.255.255.0,24h

# Captive portal redirects
address=/#/$AP_IP
EOF

    # Create dnsmasq service override
    sudo mkdir -p /etc/systemd/system/dnsmasq.service.d
    sudo tee /etc/systemd/system/dnsmasq.service.d/override.conf > /dev/null << EOF
[Unit]
After=hostapd.service
Requires=hostapd.service
ConditionPathExists=!$CONFIG_DIR/wifi-connected

[Service]
ExecStart=
ExecStart=/usr/sbin/dnsmasq --conf-file=$CONFIG_DIR/dnsmasq.conf --no-daemon
Restart=on-failure
RestartSec=5
EOF

    log_success "dnsmasq configured"
}

# Create web interface
create_web_interface() {
    log_info "Creating web interface..."
    
    # Main HTML page
    sudo tee "$WEB_DIR/index.html" > /dev/null << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>WiFi Setup</title>
    <link rel="stylesheet" href="css/style.css">
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>📶 WiFi Setup</h1>
            <p>Configure your device's WiFi connection</p>
        </div>
        
        <div id="loading" class="loading">
            <div class="spinner"></div>
            <p>Scanning for networks...</p>
        </div>
        
        <div id="error" class="error" style="display: none;">
            <p id="error-message"></p>
            <button onclick="scanNetworks()">Try Again</button>
        </div>
        
        <div id="networks" class="networks" style="display: none;">
            <h2>Available Networks</h2>
            <div id="network-list"></div>
            <button onclick="scanNetworks()" class="refresh-btn">🔄 Refresh</button>
        </div>
        
        <div id="connect-form" class="connect-form" style="display: none;">
            <h2>Connect to Network</h2>
            <form id="wifi-form">
                <div class="form-group">
                    <label for="ssid">Network Name:</label>
                    <input type="text" id="ssid" name="ssid" readonly>
                </div>
                
                <div class="form-group" id="password-group">
                    <label for="password">Password:</label>
                    <input type="password" id="password" name="password" required>
                    <button type="button" onclick="togglePassword()">👁️</button>
                </div>
                
                <div class="form-group">
                    <button type="submit">Connect</button>
                    <button type="button" onclick="goBack()">Back</button>
                </div>
            </form>
        </div>
        
        <div id="connecting" class="connecting" style="display: none;">
            <div class="spinner"></div>
            <h2>Connecting...</h2>
            <p id="connect-status">Attempting to connect to the network...</p>
        </div>
        
        <div id="success" class="success" style="display: none;">
            <h2>✅ Connected!</h2>
            <p>Successfully connected to WiFi.</p>
            <p>This setup page will now close.</p>
        </div>
    </div>
    
    <script src="js/app.js"></script>
</body>
</html>
EOF

    # CSS styling
    sudo tee "$WEB_DIR/css/style.css" > /dev/null << 'EOF'
* {
    margin: 0;
    padding: 0;
    box-sizing: border-box;
}

body {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    min-height: 100vh;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 20px;
}

.container {
    background: white;
    border-radius: 12px;
    box-shadow: 0 20px 40px rgba(0,0,0,0.1);
    padding: 30px;
    max-width: 500px;
    width: 100%;
}

.header {
    text-align: center;
    margin-bottom: 30px;
}

.header h1 {
    color: #333;
    margin-bottom: 10px;
}

.header p {
    color: #666;
}

.loading, .connecting {
    text-align: center;
    padding: 40px 20px;
}

.spinner {
    width: 40px;
    height: 40px;
    margin: 0 auto 20px;
    border: 4px solid #f3f3f3;
    border-top: 4px solid #667eea;
    border-radius: 50%;
    animation: spin 1s linear infinite;
}

@keyframes spin {
    0% { transform: rotate(0deg); }
    100% { transform: rotate(360deg); }
}

.error {
    text-align: center;
    padding: 20px;
    background: #fee;
    border: 1px solid #fcc;
    border-radius: 8px;
    color: #a00;
    margin-bottom: 20px;
}

.networks {
    margin-bottom: 20px;
}

.networks h2 {
    margin-bottom: 20px;
    color: #333;
}

.network-item {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 15px;
    margin-bottom: 10px;
    border: 2px solid #eee;
    border-radius: 8px;
    cursor: pointer;
    transition: all 0.2s;
}

.network-item:hover {
    border-color: #667eea;
    background: #f8f9ff;
}

.network-info {
    display: flex;
    align-items: center;
    gap: 10px;
}

.network-security {
    font-size: 0.9em;
    color: #666;
}

.signal-strength {
    font-size: 1.2em;
}

.form-group {
    margin-bottom: 20px;
}

.form-group label {
    display: block;
    margin-bottom: 5px;
    color: #333;
    font-weight: 500;
}

.form-group input {
    width: 100%;
    padding: 12px;
    border: 2px solid #ddd;
    border-radius: 6px;
    font-size: 16px;
    transition: border-color 0.2s;
}

.form-group input:focus {
    outline: none;
    border-color: #667eea;
}

button {
    background: #667eea;
    color: white;
    border: none;
    padding: 12px 24px;
    border-radius: 6px;
    cursor: pointer;
    font-size: 16px;
    transition: background 0.2s;
}

button:hover {
    background: #5a6fd8;
}

.refresh-btn {
    width: 100%;
    margin-top: 10px;
}

.success {
    text-align: center;
    padding: 40px 20px;
    color: #0a5d0a;
}

.success h2 {
    margin-bottom: 20px;
}

@media (max-width: 480px) {
    .container {
        padding: 20px;
        margin: 10px;
    }
    
    .network-item {
        padding: 12px;
    }
}
EOF

    # JavaScript application
    sudo tee "$WEB_DIR/js/app.js" > /dev/null << 'EOF'
class WiFiSetup {
    constructor() {
        this.currentNetworks = [];
        this.selectedNetwork = null;
        this.init();
    }
    
    init() {
        document.getElementById('wifi-form').addEventListener('submit', (e) => {
            e.preventDefault();
            this.connectToNetwork();
        });
        
        this.scanNetworks();
    }
    
    async scanNetworks() {
        this.showSection('loading');
        
        try {
            const response = await fetch('/api/scan.php');
            const data = await response.json();
            
            if (data.success) {
                this.currentNetworks = data.networks;
                this.displayNetworks();
            } else {
                this.showError(data.error || 'Failed to scan networks');
            }
        } catch (error) {
            this.showError('Network scan failed: ' + error.message);
        }
    }
    
    displayNetworks() {
        const networkList = document.getElementById('network-list');
        networkList.innerHTML = '';
        
        if (this.currentNetworks.length === 0) {
            networkList.innerHTML = '<p>No networks found. Try refreshing.</p>';
        } else {
            this.currentNetworks.forEach(network => {
                const networkItem = this.createNetworkItem(network);
                networkList.appendChild(networkItem);
            });
        }
        
        this.showSection('networks');
    }
    
    createNetworkItem(network) {
        const item = document.createElement('div');
        item.className = 'network-item';
        item.onclick = () => this.selectNetwork(network);
        
        const signalIcon = this.getSignalIcon(network.signal);
        const securityText = network.encrypted ? '🔒 Secured' : '🔓 Open';
        
        item.innerHTML = `
            <div class="network-info">
                <span class="signal-strength">${signalIcon}</span>
                <div>
                    <div><strong>${network.ssid}</strong></div>
                    <div class="network-security">${securityText}</div>
                </div>
            </div>
        `;
        
        return item;
    }
    
    getSignalIcon(signal) {
        const strength = Math.abs(signal);
        if (strength <= 30) return '📶';
        if (strength <= 50) return '📶';
        if (strength <= 70) return '📶';
        return '📶';
    }
    
    selectNetwork(network) {
        this.selectedNetwork = network;
        document.getElementById('ssid').value = network.ssid;
        
        const passwordGroup = document.getElementById('password-group');
        if (network.encrypted) {
            passwordGroup.style.display = 'block';
            document.getElementById('password').required = true;
        } else {
            passwordGroup.style.display = 'none';
            document.getElementById('password').required = false;
        }
        
        this.showSection('connect-form');
    }
    
    async connectToNetwork() {
        const ssid = document.getElementById('ssid').value;
        const password = document.getElementById('password').value;
        
        this.showSection('connecting');
        document.getElementById('connect-status').textContent = 'Attempting to connect...';
        
        try {
            const response = await fetch('/api/connect.php', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({
                    ssid: ssid,
                    password: password
                })
            });
            
            const data = await response.json();
            
            if (data.success) {
                document.getElementById('connect-status').textContent = 'Connected! Shutting down setup...';
                setTimeout(() => {
                    this.showSection('success');
                    setTimeout(() => {
                        window.location.href = '/shutdown';
                    }, 3000);
                }, 2000);
            } else {
                this.showError(data.error || 'Connection failed');
            }
        } catch (error) {
            this.showError('Connection failed: ' + error.message);
        }
    }
    
    showSection(sectionName) {
        const sections = ['loading', 'error', 'networks', 'connect-form', 'connecting', 'success'];
        sections.forEach(section => {
            document.getElementById(section).style.display = 'none';
        });
        document.getElementById(sectionName).style.display = 'block';
    }
    
    showError(message) {
        document.getElementById('error-message').textContent = message;
        this.showSection('error');
    }
    
    goBack() {
        this.showSection('networks');
    }
    
    togglePassword() {
        const passwordInput = document.getElementById('password');
        passwordInput.type = passwordInput.type === 'password' ? 'text' : 'password';
    }
}

// Global functions for HTML onclick handlers
function scanNetworks() {
    if (window.wifiSetup) {
        window.wifiSetup.scanNetworks();
    }
}

function goBack() {
    if (window.wifiSetup) {
        window.wifiSetup.goBack();
    }
}

function togglePassword() {
    if (window.wifiSetup) {
        window.wifiSetup.togglePassword();
    }
}

// Initialize the app
document.addEventListener('DOMContentLoaded', () => {
    window.wifiSetup = new WiFiSetup();
});
EOF

    log_success "Web interface created"
}

# Create PHP API endpoints
create_api_endpoints() {
    log_info "Creating API endpoints..."
    
    # Scan networks API
    sudo tee "$WEB_DIR/api/scan.php" > /dev/null << 'EOF'
<?php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');

function scanWifiNetworks() {
    $output = [];
    $returnVar = 0;
    
    // Use iw to scan for networks
    exec('sudo iw dev wlan0 scan 2>/dev/null | grep -E "(SSID|signal|Privacy)" 2>/dev/null', $output, $returnVar);
    
    $networks = [];
    $currentNetwork = [];
    
    foreach ($output as $line) {
        $line = trim($line);
        
        if (strpos($line, 'SSID:') !== false) {
            if (!empty($currentNetwork)) {
                $networks[] = $currentNetwork;
            }
            $ssid = trim(str_replace('SSID:', '', $line));
            if (!empty($ssid)) {
                $currentNetwork = [
                    'ssid' => $ssid,
                    'signal' => -100,
                    'encrypted' => false
                ];
            }
        } elseif (strpos($line, 'signal:') !== false) {
            preg_match('/-?\d+/', $line, $matches);
            if (!empty($matches)) {
                $currentNetwork['signal'] = intval($matches[0]);
            }
        } elseif (strpos($line, 'Privacy') !== false) {
            $currentNetwork['encrypted'] = true;
        }
    }
    
    if (!empty($currentNetwork)) {
        $networks[] = $currentNetwork;
    }
    
    // Remove duplicates and sort by signal strength
    $unique_networks = [];
    foreach ($networks as $network) {
        if (!empty($network['ssid']) && $network['ssid'] !== '') {
            $unique_networks[$network['ssid']] = $network;
        }
    }
    
    $networks = array_values($unique_networks);
    usort($networks, function($a, $b) {
        return $b['signal'] - $a['signal'];
    });
    
    return $networks;
}

try {
    $networks = scanWifiNetworks();
    echo json_encode([
        'success' => true,
        'networks' => $networks
    ]);
} catch (Exception $e) {
    echo json_encode([
        'success' => false,
        'error' => $e->getMessage()
    ]);
}
?>
EOF

    # Connect to network API
    sudo tee "$WEB_DIR/api/connect.php" > /dev/null << 'EOF'
<?php
header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');

$input = json_decode(file_get_contents('php://input'), true);

if (!$input || !isset($input['ssid'])) {
    echo json_encode([
        'success' => false,
        'error' => 'SSID is required'
    ]);
    exit;
}

$ssid = escapeshellarg($input['ssid']);
$password = isset($input['password']) ? escapeshellarg($input['password']) : '';

try {
    // Create NetworkManager connection
    if (!empty($password)) {
        $cmd = "sudo nmcli dev wifi connect $ssid password $password 2>&1";
    } else {
        $cmd = "sudo nmcli dev wifi connect $ssid 2>&1";
    }
    
    exec($cmd, $output, $returnVar);
    
    if ($returnVar === 0) {
        // Mark as connected and trigger shutdown
        file_put_contents('/etc/wifi-provisioning/wifi-connected', date('Y-m-d H:i:s'));
        
        // Trigger service shutdown in background
        exec('sudo systemctl stop wifi-provisioning 2>/dev/null &');
        
        echo json_encode([
            'success' => true,
            'message' => 'Connected successfully'
        ]);
    } else {
        echo json_encode([
            'success' => false,
            'error' => 'Connection failed: ' . implode(' ', $output)
        ]);
    }
} catch (Exception $e) {
    echo json_encode([
        'success' => false,
        'error' => $e->getMessage()
    ]);
}
?>
EOF

    # Set correct permissions for PHP files
    sudo chown -R www-data:www-data "$WEB_DIR/api"
    sudo chmod 755 "$WEB_DIR/api"/*.php
    
    log_success "API endpoints created"
}

# Configure nginx
configure_nginx() {
    log_info "Configuring nginx..."
    
    # Get PHP version
    PHP_VERSION=$(php -v | head -1 | cut -d' ' -f2 | cut -d'.' -f1,2)
    
    sudo tee "$CONFIG_DIR/nginx.conf" > /dev/null << EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    
    root $WEB_DIR;
    index index.html index.php;
    
    server_name _;
    
    # Captive portal redirects
    location / {
        try_files \$uri \$uri/ /index.html;
    }
    
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php${PHP_VERSION}-fpm.sock;
    }
    
    location /shutdown {
        return 200 "Shutting down setup mode...";
        add_header Content-Type text/plain;
    }
    
    # Deny access to sensitive files
    location ~ /\. {
        deny all;
    }
}
EOF

    # Link nginx config
    sudo ln -sf "$CONFIG_DIR/nginx.conf" /etc/nginx/sites-available/wifi-setup
    sudo ln -sf /etc/nginx/sites-available/wifi-setup /etc/nginx/sites-enabled/wifi-setup
    sudo rm -f /etc/nginx/sites-enabled/default
    
    log_success "nginx configured"
}

# Create network management scripts
create_network_scripts() {
    log_info "Creating network management scripts..."
    
    # AP startup script
    sudo tee "$CONFIG_DIR/scripts/start-ap.sh" > /dev/null << EOF
#!/bin/bash
set -euo pipefail

log() { echo "\$(date): \$1" >> /var/log/wifi-provisioning/ap.log; }

log "Starting WiFi access point..."

# Disable NetworkManager management of the interface
sudo nmcli dev set $AP_INTERFACE managed no 2>/dev/null || true

# Bring interface down and up
sudo ip link set $AP_INTERFACE down
sudo ip link set $AP_INTERFACE up

# Configure IP address
sudo ip addr flush dev $AP_INTERFACE
sudo ip addr add $AP_IP/24 dev $AP_INTERFACE

# Enable IP forwarding
echo 1 | sudo tee /proc/sys/net/ipv4/ip_forward > /dev/null

log "Access point interface configured"
EOF

    # AP shutdown script
    sudo tee "$CONFIG_DIR/scripts/stop-ap.sh" > /dev/null << EOF
#!/bin/bash
set -euo pipefail

log() { echo "\$(date): \$1" >> /var/log/wifi-provisioning/ap.log; }

log "Stopping WiFi access point..."

# Stop services
sudo systemctl stop hostapd 2>/dev/null || true
sudo systemctl stop dnsmasq 2>/dev/null || true
sudo systemctl stop nginx 2>/dev/null || true
sudo systemctl stop php*-fpm 2>/dev/null || true

# Re-enable NetworkManager management
sudo nmcli dev set $AP_INTERFACE managed yes 2>/dev/null || true

# Flush IP configuration
sudo ip addr flush dev $AP_INTERFACE 2>/dev/null || true

log "Access point stopped"
EOF

    # Make scripts executable
    sudo chmod +x "$CONFIG_DIR/scripts"/*.sh
    
    log_success "Network management scripts created"
}

# Create main service
create_main_service() {
    log_info "Creating main WiFi provisioning service..."
    
    sudo tee /etc/systemd/system/wifi-provisioning.service > /dev/null << EOF
[Unit]
Description=WiFi Provisioning System
After=network.target
Wants=network.target
ConditionPathExists=!$CONFIG_DIR/wifi-connected

[Service]
Type=forking
ExecStartPre=$CONFIG_DIR/scripts/start-ap.sh
ExecStart=/bin/bash -c 'systemctl start hostapd dnsmasq php${PHP_VERSION}-fpm nginx'
ExecStop=$CONFIG_DIR/scripts/stop-ap.sh
RemainAfterExit=yes
Restart=no
TimeoutStartSec=60
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
EOF

    log_success "Main service created"
}

# Configure sudoers for web interface
configure_sudoers() {
    log_info "Configuring sudoers for web interface..."
    
    sudo tee /etc/sudoers.d/wifi-provisioning > /dev/null << EOF
# Allow www-data to execute network commands for WiFi provisioning
www-data ALL=(ALL) NOPASSWD: /sbin/iw
www-data ALL=(ALL) NOPASSWD: /usr/bin/nmcli
www-data ALL=(ALL) NOPASSWD: /bin/systemctl stop wifi-provisioning
www-data ALL=(ALL) NOPASSWD: /bin/systemctl start wifi-provisioning
EOF

    log_success "Sudoers configured"
}

# Create monitoring and health check scripts
create_monitoring() {
    log_info "Creating monitoring scripts..."
    
    # Health check script
    sudo tee "$CONFIG_DIR/scripts/health-check.sh" > /dev/null << EOF
#!/bin/bash
# Health check for WiFi provisioning system

check_service() {
    local service=\$1
    if systemctl is-active --quiet "\$service"; then
        echo "✓ \$service is running"
        return 0
    else
        echo "✗ \$service is not running"
        return 1
    fi
}

echo "WiFi Provisioning System Health Check"
echo "====================================="

errors=0

# Check if we should be running
if [[ -f "$CONFIG_DIR/wifi-connected" ]]; then
    echo "ℹ️  WiFi is connected, provisioning system should be inactive"
    exit 0
fi

# Check required services
check_service hostapd || ((errors++))
check_service dnsmasq || ((errors++))
check_service nginx || ((errors++))
check_service php*-fpm || ((errors++))

# Check network interface
if ip addr show $AP_INTERFACE | grep -q "$AP_IP"; then
    echo "✓ Network interface $AP_INTERFACE is configured"
else
    echo "✗ Network interface $AP_INTERFACE is not configured"
    ((errors++))
fi

# Check web interface
if curl -s http://localhost >/dev/null; then
    echo "✓ Web interface is accessible"
else
    echo "✗ Web interface is not accessible"
    ((errors++))
fi

if [[ \$errors -eq 0 ]]; then
    echo "✅ All checks passed"
    exit 0
else
    echo "❌ \$errors errors found"
    exit 1
fi
EOF

    sudo chmod +x "$CONFIG_DIR/scripts/health-check.sh"
    
    # Create health check timer
    sudo tee /etc/systemd/system/wifi-provisioning-health.service > /dev/null << EOF
[Unit]
Description=WiFi Provisioning Health Check
After=wifi-provisioning.service

[Service]
Type=oneshot
ExecStart=$CONFIG_DIR/scripts/health-check.sh
User=root
EOF

    sudo tee /etc/systemd/system/wifi-provisioning-health.timer > /dev/null << EOF
[Unit]
Description=WiFi Provisioning Health Check Timer
Requires=wifi-provisioning-health.service

[Timer]
OnActiveSec=60
OnUnitActiveSec=300
AccuracySec=30

[Install]
WantedBy=timers.target
EOF

    log_success "Monitoring scripts created"
}

# Create test suite
create_tests() {
    log_info "Creating test suite..."
    
    sudo tee "$CONFIG_DIR/scripts/test-system.sh" > /dev/null << 'EOF'
#!/bin/bash
# Comprehensive test suite for WiFi provisioning system

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

passed=0
failed=0

test_pass() {
    echo -e "${GREEN}✓ PASS:${NC} $1"
    ((passed++))
}

test_fail() {
    echo -e "${RED}✗ FAIL:${NC} $1"
    ((failed++))
}

test_warn() {
    echo -e "${YELLOW}⚠ WARN:${NC} $1"
}

echo "WiFi Provisioning System Test Suite"
echo "===================================="

# Test 1: Check configuration files
echo "Testing configuration files..."
for file in "/etc/wifi-provisioning/hostapd.conf" "/etc/wifi-provisioning/dnsmasq.conf" "/etc/wifi-provisioning/nginx.conf"; do
    if [[ -f "$file" ]]; then
        test_pass "Configuration file exists: $file"
    else
        test_fail "Configuration file missing: $file"
    fi
done

# Test 2: Check required binaries
echo "Testing required binaries..."
for binary in "hostapd" "dnsmasq" "nginx" "php-fpm" "iw" "nmcli"; do
    if command -v "$binary" >/dev/null 2>&1; then
        test_pass "Binary available: $binary"
    else
        test_fail "Binary missing: $binary"
    fi
done

# Test 3: Check service files
echo "Testing systemd services..."
for service in "wifi-provisioning" "wifi-provisioning-health"; do
    if [[ -f "/etc/systemd/system/$service.service" ]]; then
        test_pass "Service file exists: $service"
    else
        test_fail "Service file missing: $service"
    fi
done

# Test 4: Check web interface files
echo "Testing web interface..."
for file in "/var/www/wifi-setup/index.html" "/var/www/wifi-setup/css/style.css" "/var/www/wifi-setup/js/app.js"; do
    if [[ -f "$file" ]]; then
        test_pass "Web file exists: $file"
    else
        test_fail "Web file missing: $file"
    fi
done

# Test 5: Check API endpoints
echo "Testing API endpoints..."
for file in "/var/www/wifi-setup/api/scan.php" "/var/www/wifi-setup/api/connect.php"; do
    if [[ -f "$file" ]]; then
        test_pass "API endpoint exists: $file"
    else
        test_fail "API endpoint missing: $file"
    fi
done

# Test 6: Check permissions
echo "Testing file permissions..."
if [[ -O "/var/www/wifi-setup" ]]; then
    test_pass "Web directory has correct ownership"
else
    test_fail "Web directory ownership incorrect"
fi

# Test 7: Check sudoers configuration
echo "Testing sudoers configuration..."
if [[ -f "/etc/sudoers.d/wifi-provisioning" ]]; then
    test_pass "Sudoers configuration exists"
else
    test_fail "Sudoers configuration missing"
fi

# Test 8: Network interface check
echo "Testing network interface..."
if iw dev | grep -q "Interface"; then
    test_pass "Wireless interface available"
else
    test_fail "No wireless interface found"
fi

# Test 9: Service simulation test
echo "Testing service configuration..."
if systemctl list-unit-files | grep -q "wifi-provisioning.service"; then
    test_pass "Main service is configured"
else
    test_fail "Main service not configured"
fi

echo ""
echo "Test Results:"
echo "============="
echo -e "${GREEN}Passed: $passed${NC}"
echo -e "${RED}Failed: $failed${NC}"

if [[ $failed -eq 0 ]]; then
    echo -e "${GREEN}🎉 All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}💥 $failed tests failed${NC}"
    exit 1
fi
EOF

    sudo chmod +x "$CONFIG_DIR/scripts/test-system.sh"
    
    log_success "Test suite created"
}

# Create uninstall script
create_uninstall_script() {
    log_info "Creating uninstall script..."
    
    tee "$SCRIPT_DIR/uninstall-wifi-provisioning.sh" > /dev/null << 'EOF'
#!/bin/bash
# Uninstall script for WiFi provisioning system

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}Uninstalling WiFi Provisioning System...${NC}"

# Stop and disable services
sudo systemctl stop wifi-provisioning 2>/dev/null || true
sudo systemctl disable wifi-provisioning 2>/dev/null || true
sudo systemctl stop wifi-provisioning-health.timer 2>/dev/null || true
sudo systemctl disable wifi-provisioning-health.timer 2>/dev/null || true

# Remove service files
sudo rm -f /etc/systemd/system/wifi-provisioning.service
sudo rm -f /etc/systemd/system/wifi-provisioning-health.service
sudo rm -f /etc/systemd/system/wifi-provisioning-health.timer

# Remove configuration directory
sudo rm -rf /etc/wifi-provisioning

# Remove web directory
sudo rm -rf /var/www/wifi-setup

# Remove nginx site
sudo rm -f /etc/nginx/sites-available/wifi-setup
sudo rm -f /etc/nginx/sites-enabled/wifi-setup

# Remove sudoers file
sudo rm -f /etc/sudoers.d/wifi-provisioning

# Remove log directory
sudo rm -rf /var/log/wifi-provisioning

# Reload systemd
sudo systemctl daemon-reload

# Restart nginx to default config
sudo systemctl restart nginx 2>/dev/null || true

echo -e "${GREEN}WiFi Provisioning System uninstalled successfully!${NC}"
EOF

    chmod +x "$SCRIPT_DIR/uninstall-wifi-provisioning.sh"
    
    log_success "Uninstall script created"
}

# Final setup and enable services
finalize_setup() {
    log_info "Finalizing setup..."
    
    # Reload systemd
    sudo systemctl daemon-reload
    
    # Enable services
    sudo systemctl enable wifi-provisioning.service
    sudo systemctl enable wifi-provisioning-health.timer
    
    # Start health monitoring
    sudo systemctl start wifi-provisioning-health.timer
    
    # Create initial log files
    sudo touch /var/log/wifi-provisioning/{system.log,ap.log,nginx.log}
    sudo chown -R syslog:adm /var/log/wifi-provisioning
    
    log_success "Setup finalized"
}

# Run tests
run_tests() {
    log_info "Running system tests..."
    
    if sudo "$CONFIG_DIR/scripts/test-system.sh"; then
        log_success "All tests passed!"
    else
        log_error "Some tests failed. Check the output above."
        exit 1
    fi
}

# Display final instructions
show_final_instructions() {
    local hostname=$(hostname)
    
    cat << EOF

${GREEN}🎉 WiFi Provisioning System Installation Complete!${NC}

${BLUE}System Overview:${NC}
• Hotspot SSID: ${YELLOW}$AP_SSID${NC}
• Portal IP: ${YELLOW}$AP_IP${NC}
• Web Interface: ${YELLOW}http://$AP_IP${NC}

${BLUE}How it works:${NC}
1. When no WiFi connection exists, the system automatically starts an access point
2. Users connect to the "$AP_SSID" network (no password required)
3. A captive portal guides them through WiFi selection and password entry
4. Once connected, the access point shuts down automatically

${BLUE}Management Commands:${NC}
• Start provisioning: ${YELLOW}sudo systemctl start wifi-provisioning${NC}
• Stop provisioning:  ${YELLOW}sudo systemctl stop wifi-provisioning${NC}
• Check status:       ${YELLOW}sudo systemctl status wifi-provisioning${NC}
• View logs:          ${YELLOW}sudo journalctl -u wifi-provisioning -f${NC}
• Health check:       ${YELLOW}sudo $CONFIG_DIR/scripts/health-check.sh${NC}
• Run tests:          ${YELLOW}sudo $CONFIG_DIR/scripts/test-system.sh${NC}

${BLUE}Troubleshooting:${NC}
• Force reset:        ${YELLOW}sudo rm -f $CONFIG_DIR/wifi-connected && sudo systemctl restart wifi-provisioning${NC}
• Check logs:         ${YELLOW}sudo tail -f /var/log/wifi-provisioning/system.log${NC}

${BLUE}Uninstall:${NC}
• Run: ${YELLOW}$SCRIPT_DIR/uninstall-wifi-provisioning.sh${NC}

${GREEN}🚀 Ready to use! Reboot to activate the WiFi provisioning system.${NC}

EOF
}

# Main installation function
main() {
    log_info "Starting WiFi Provisioning System installation..."
    
    # Update todo
    sudo mkdir -p "$(dirname "$LOG_FILE")"
    sudo touch "$LOG_FILE"
    
    check_requirements
    install_dependencies
    create_directories
    configure_hostapd
    configure_dnsmasq
    create_web_interface
    create_api_endpoints
    configure_nginx
    create_network_scripts
    create_main_service
    configure_sudoers
    create_monitoring
    create_tests
    create_uninstall_script
    finalize_setup
    run_tests
    show_final_instructions
    
    echo
    read -p "Would you like to reboot now to activate the system? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log_info "Rebooting system..."
        sudo reboot
    else
        log_info "Please reboot manually when ready: sudo reboot"
    fi
}

# Entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi