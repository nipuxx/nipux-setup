# NiPux Ethernet-First Network Management System

🚀 **Production-grade, ethernet-first network management with WiFi fallback** 

Intelligent network management that prioritizes ethernet connections and automatically provides WiFi provisioning when ethernet is unavailable. Perfect for headless server deployments that need robust network connectivity.

## ✨ Features

- **Ethernet-First**: Prioritizes ethernet connections for maximum reliability
- **Automatic Fallback**: Seamlessly switches to WiFi provisioning when ethernet unavailable
- **Fully Offline**: Works without internet connectivity during setup
- **Production Ready**: Comprehensive error handling, logging, monitoring
- **Self-Contained**: All dependencies included or bundled
- **Intelligent Monitoring**: Continuously monitors network state and adapts
- **User-Friendly**: Mobile-responsive captive portal interface
- **Robust**: Health checks, recovery mechanisms, comprehensive testing

## 🎯 How It Works

1. **Ethernet Monitor** → Continuously monitors ethernet connection status
2. **Ethernet Priority** → Uses ethernet when available, WiFi provisioning stays inactive
3. **Auto Fallback** → When ethernet disconnected, automatically starts WiFi provisioning
4. **Access Point** → Creates `{hostname}-setup` hotspot for WiFi configuration
5. **Captive Portal** → User connects and gets redirected to setup page
6. **WiFi Selection** → Scan networks, select, and enter password
7. **Auto-Connect** → Connects to WiFi and shuts down access point
8. **Smart Resume** → System uses WiFi until ethernet is reconnected

## 🚀 Quick Start (Ubuntu Server)

### One-Command Installation
```bash
# 1. Connect ethernet cable and ensure internet access
# 2. Clone repository and run installer
git clone <this-repo> nipux-setup
cd nipux-setup

# 3. Run the installer - handles everything automatically
chmod +x setup.sh
./setup.sh

# 4. Reboot when prompted
# 5. System now monitors ethernet and provides WiFi fallback automatically
```

### System Behavior After Installation

**With Ethernet Connected:**
- Normal operation using ethernet connection
- WiFi provisioning remains inactive
- No access point created

**Ethernet Disconnected:**
- System automatically detects disconnection
- Starts WiFi provisioning mode within 30 seconds
- Creates `{hostname}-setup` access point
- User can connect and configure WiFi

**After WiFi Configuration:**
- System connects to configured WiFi
- Access point automatically shuts down
- Continues monitoring for ethernet reconnection

### Alternative Installation Methods
```bash
# Alternative: Let the system choose the best installer
chmod +x setup.sh
./setup.sh
```

### Method 3: Manual Component Installation
```bash
# For troubleshooting: Run individual components
./diagnose-wifi.sh          # Check hardware first
./install-dependencies.sh   # Install packages
./setup-wifi-provisioning.sh # Configure system
```

## 📋 Requirements

- **OS**: Ubuntu Server 18.04+ or Debian 10+
- **Hardware**: WiFi adapter capable of AP mode
- **Memory**: 512MB RAM minimum
- **Storage**: 2GB free disk space
- **Access**: sudo privileges

## 🌐 User Experience

### For End Users
1. Look for WiFi network: `{hostname}-setup`
2. Connect (no password required)
3. Browser automatically opens setup page
4. Select WiFi network and enter password
5. System connects and setup completes

### Access Point Details
- **SSID**: `{hostname}-setup` (e.g., `ubuntu-server-setup`)
- **IP Address**: `192.168.4.1`
- **DHCP Range**: `192.168.4.10-50`
- **Portal URL**: `http://192.168.4.1`

## 🛠️ Management Commands

```bash
# Quick status check (auto-created helper)
./status.sh

# Force WiFi provisioning mode (auto-created helper)  
./reset.sh

# Check ethernet monitoring service
sudo systemctl status nipux-ethernet-monitor

# Check WiFi provisioning service
sudo systemctl status wifi-provisioning

# View real-time monitoring logs
sudo journalctl -u nipux-ethernet-monitor -f

# View WiFi provisioning logs
sudo journalctl -u wifi-provisioning -f

# Check current network status
sudo /usr/local/bin/nipux-ethernet-monitor status

# Run health check
sudo /etc/wifi-provisioning/scripts/health-check.sh

# Run system tests
sudo /etc/wifi-provisioning/scripts/test-system.sh

# Manual force WiFi provisioning (disconnect all and restart monitor)
sudo rm -f /etc/nipux/active-ethernet /etc/nipux/network-status
sudo systemctl restart nipux-ethernet-monitor

# Emergency stop all services
sudo systemctl stop nipux-ethernet-monitor wifi-provisioning
```

## 📁 Project Structure

```
nipux-setup/
├── setup.sh                     # 🎯 MAIN INSTALLER (start here!)
├── ethernet-monitor.sh          # 🔍 Ethernet monitoring service core
├── install.sh                   # 🔧 Auto-detecting installer wrapper
├── diagnose-wifi.sh             # 🔍 Hardware diagnostic tool
├── setup-wifi-provisioning.sh   # WiFi provisioning system installer
├── setup-wifi-connect.sh        # WiFi Connect fallback installer  
├── install-dependencies.sh      # System dependency installer
├── download-packages.sh         # Download offline packages
├── prepare-offline-package.sh   # Prepare packages for offline use
├── offline-packages/            # Pre-downloaded Ubuntu packages
│   ├── amd64/                   # x86_64 packages
│   └── install-offline-packages.sh
├── offline-deps/                # Essential packages
├── status.sh                    # 📊 Check system status (auto-created)
├── reset.sh                     # 🔄 Force WiFi setup mode (auto-created)
├── DEPLOYMENT.md                # Detailed deployment guide
├── QUICK-START.md               # Quick reference guide
└── README.md                    # This file
```

## 🔧 Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Ethernet      │────│  Ubuntu Server   │────│ WiFi Network    │
│   Connection    │    │   (Primary)      │    │   (Fallback)    │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                              │
                              ▼
                       ┌──────────────────┐
                       │ Ethernet Monitor │
                       │  Service (Core)  │
                       └──────────────────┘
                              │
                              ▼
            ┌─────────────────────────────────────────┐
            │           WiFi Provisioning             │
            │      (Activated when needed)            │
            └─────────────────────────────────────────┘
                              │
    ┌─────────────────┐       ▼        ┌──────────────────┐
    │   Mobile Device │────────────────│  Access Point    │
    │   (Phone/Laptop)│                │  192.168.4.1     │
    └─────────────────┘                └──────────────────┘
                                              │
                                              ▼
                                       ┌──────────────────┐
                                       │  Captive Portal  │
                                       │  (nginx + PHP)   │
                                       └──────────────────┘
```

## 🔍 Components

- **nipux-ethernet-monitor**: Core service that monitors ethernet and controls WiFi provisioning
- **hostapd**: Creates WiFi access point when needed
- **dnsmasq**: Provides DHCP and DNS services for access point
- **nginx**: Serves captive portal web interface
- **PHP**: Handles WiFi scanning and connection API
- **NetworkManager**: Manages both ethernet and WiFi connections
- **systemd**: Service management and monitoring

## 📊 Monitoring & Logs

### Log Locations
- **System**: `/var/log/wifi-provisioning/system.log`
- **Access Point**: `/var/log/wifi-provisioning/ap.log` 
- **Web Server**: `/var/log/nginx/access.log`
- **Service**: `journalctl -u wifi-provisioning`

### Health Monitoring
- Automatic health checks every 5 minutes
- Service restart on failure
- Network interface monitoring
- Web portal accessibility checks

## 🧪 Testing

```bash
# Run comprehensive test suite
sudo /etc/wifi-provisioning/scripts/test-system.sh

# Manual testing checklist
# □ Boot without WiFi - AP starts automatically
# □ Connect mobile device to AP
# □ Captive portal opens in browser
# □ Can scan and see available networks
# □ Can connect to test WiFi network
# □ AP shuts down after connection
# □ WiFi persists after reboot
```

## 🔒 Security

- **Open AP**: Intentionally unencrypted for easy access
- **Isolated Network**: Separate 192.168.4.0/24 subnet
- **Time-Limited**: Shuts down after successful configuration
- **No Internet**: AP doesn't bridge to internet during setup
- **Local Only**: Web interface only accessible from AP clients

## 🛠️ Troubleshooting

### Common Issues

**AP Not Starting**
```bash
sudo systemctl status hostapd
sudo rfkill list
sudo iw dev
```

**Captive Portal Not Loading**
```bash
sudo systemctl status nginx
curl -v http://192.168.4.1
```

**WiFi Connection Fails**
```bash
sudo journalctl -u NetworkManager -f
sudo nmcli dev wifi list
```

**Service Stuck**
```bash
sudo systemctl stop wifi-provisioning
sudo systemctl start wifi-provisioning
```

## 🗑️ Uninstall

```bash
# Automatic uninstaller (created during setup)
./uninstall-wifi-provisioning.sh

# Manual removal
sudo systemctl stop wifi-provisioning
sudo systemctl disable wifi-provisioning
sudo rm -rf /etc/wifi-provisioning
sudo rm -rf /var/www/wifi-setup
sudo systemctl daemon-reload
```

## 🚀 Deployment Scenarios

### USB Drive Deployment
1. Download this repository to USB drive
2. Insert USB into Ubuntu Server
3. Copy files and run setup script
4. Remove USB and reboot

### Remote Deployment
1. Upload via SCP/SFTP when internet available
2. Run setup script
3. System ready for offline WiFi provisioning

### Field Installation
1. Pre-configure on test device
2. Clone SD card/storage to production devices
3. Devices auto-configure WiFi on first boot

## 📚 Documentation

- **[DEPLOYMENT.md](DEPLOYMENT.md)** - Comprehensive deployment guide
- **[API Documentation](docs/API.md)** - Web interface API reference
- **[Troubleshooting Guide](docs/TROUBLESHOOTING.md)** - Common issues and solutions

## 🤝 Contributing

1. Test on your Ubuntu Server setup
2. Report issues with system logs
3. Submit pull requests with improvements
4. Update documentation for clarity

## 📄 License

MIT License - Feel free to use in production environments.

## 🔗 References

- [hostapd Documentation](https://w1.fi/hostapd/)
- [NetworkManager Guide](https://networkmanager.dev/)
- [Ubuntu Server Documentation](https://ubuntu.com/server/docs)

---

**Ready for production deployment on Ubuntu Server! 🎉**