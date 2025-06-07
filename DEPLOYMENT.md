# Production Deployment Guide

## Overview

This WiFi provisioning system creates a production-grade, offline-capable solution for Ubuntu Server devices. It automatically hosts an access point when no internet connection is available, allowing users to configure WiFi through a web interface.

## 🎯 Key Features

- **Offline Operation**: Works without internet connectivity
- **Self-Contained**: All dependencies bundled or auto-installed
- **Robust Error Handling**: Comprehensive recovery mechanisms
- **Production Ready**: Logging, monitoring, and health checks
- **User-Friendly**: Mobile-responsive captive portal
- **Automatic**: Starts on boot when no WiFi connection exists

## 📋 Requirements

### Hardware
- Ubuntu Server 18.04+ or Debian 10+
- WiFi adapter capable of AP mode (most modern adapters)
- Minimum 512MB RAM
- 2GB free disk space

### Software Prerequisites
- sudo access
- systemd-based system
- Basic networking tools (automatically installed)

## 🚀 Quick Deployment

### 1. USB Drive Preparation
```bash
# On a machine with internet access
git clone <this-repo>
cd nipux-setup

# Download offline packages (optional but recommended)
./install-dependencies.sh
cd dependencies
./download-packages.sh
```

### 2. Target Device Installation
```bash
# Copy files to target device via USB
sudo mount /dev/sdb1 /mnt/usb
cp -r /mnt/usb/nipux-setup /home/user/

# Run installation
cd /home/user/nipux-setup
chmod +x *.sh
./setup-wifi-provisioning.sh

# Reboot to activate
sudo reboot
```

## 🔧 Detailed Setup Process

### Phase 1: Dependency Installation
The system automatically installs required packages:
- **hostapd**: Access point daemon
- **dnsmasq**: DHCP and DNS server
- **nginx**: Web server
- **php-fpm**: PHP processor
- **iw/wireless-tools**: WiFi management
- **NetworkManager**: Network configuration

### Phase 2: Service Configuration
Creates and configures:
- Access point configuration (`hostapd.conf`)
- DHCP server configuration (`dnsmasq.conf`)
- Web server with captive portal
- Network management scripts
- Health monitoring system

### Phase 3: Web Interface Deployment
- Responsive HTML5 interface
- JavaScript-based network scanning
- PHP API for WiFi operations
- Automatic captive portal detection

## 🌐 System Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Mobile Device │────│  Access Point    │────│ Target Device   │
│   (Phone/Laptop)│    │  192.168.4.1     │    │ (Ubuntu Server) │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                              │
                              ▼
                       ┌──────────────────┐
                       │  Captive Portal  │
                       │  Web Interface   │
                       └──────────────────┘
                              │
                              ▼
                       ┌──────────────────┐
                       │ NetworkManager   │
                       │ WiFi Connection  │
                       └──────────────────┘
```

## 🔄 Operation Flow

1. **Boot Detection**: System checks for existing WiFi connection
2. **AP Activation**: If no connection, starts access point mode
3. **User Connection**: User connects to `{hostname}-setup` network
4. **Portal Redirect**: Captive portal automatically opens
5. **Network Selection**: User selects WiFi and enters password
6. **Connection**: System connects to selected WiFi
7. **AP Shutdown**: Access point automatically stops
8. **Normal Operation**: System operates with WiFi connection

## 📊 Monitoring & Management

### Health Monitoring
```bash
# Check system status
sudo /etc/wifi-provisioning/scripts/health-check.sh

# View real-time logs
sudo journalctl -u wifi-provisioning -f

# Check service status
sudo systemctl status wifi-provisioning
```

### Manual Controls
```bash
# Force start provisioning mode
sudo rm -f /etc/wifi-provisioning/wifi-connected
sudo systemctl start wifi-provisioning

# Stop provisioning mode
sudo systemctl stop wifi-provisioning

# Emergency reset
sudo systemctl stop wifi-provisioning
sudo systemctl start wifi-provisioning
```

### Log Files
- **System Logs**: `/var/log/wifi-provisioning/system.log`
- **Access Point**: `/var/log/wifi-provisioning/ap.log`
- **Web Server**: `/var/log/nginx/access.log`
- **Service Logs**: `journalctl -u wifi-provisioning`

## 🛡️ Security Considerations

### Access Point Security
- **Open Network**: AP is intentionally unencrypted for ease of access
- **Isolated Segment**: Creates separate network segment (192.168.4.0/24)
- **Time-Limited**: Automatically shuts down after successful configuration
- **No Internet**: AP doesn't provide internet access during setup

### Web Portal Security
- **HTTP Protocol**: Uses HTTP for compatibility with captive portal detection
- **Local Network**: Only accessible from devices connected to the AP
- **No Persistence**: Credentials are handled by NetworkManager, not stored
- **Restricted Access**: PHP scripts have limited sudo permissions

### Production Hardening
```bash
# Optional: Restrict SSH during provisioning
sudo ufw enable
sudo ufw allow ssh
sudo ufw allow 80/tcp
sudo ufw allow 53/udp

# Optional: Change default AP name
sudo sed -i 's/setup/production-config/' /etc/wifi-provisioning/hostapd.conf
```

## 🧪 Testing & Validation

### Automated Tests
```bash
# Run comprehensive test suite
sudo /etc/wifi-provisioning/scripts/test-system.sh

# Test individual components
sudo nginx -t
sudo hostapd -t /etc/wifi-provisioning/hostapd.conf
```

### Manual Testing Checklist
- [ ] Boot without WiFi - AP should start automatically
- [ ] Connect mobile device to AP
- [ ] Captive portal opens automatically
- [ ] Can scan and see available networks
- [ ] Can connect to test WiFi network
- [ ] AP shuts down after successful connection
- [ ] Device maintains WiFi connection after reboot

### Performance Testing
```bash
# Check memory usage
free -h

# Check CPU usage during AP operation
top -p $(pgrep hostapd)

# Test concurrent connections (max 10)
for i in {1..5}; do
    curl -s http://192.168.4.1 &
done
```

## 🔧 Troubleshooting

### Common Issues

#### AP Not Starting
```bash
# Check interface status
sudo iw dev

# Check for conflicts
sudo systemctl status NetworkManager
sudo rfkill list

# Manual interface reset
sudo systemctl stop NetworkManager
sudo systemctl start wifi-provisioning
```

#### Captive Portal Not Loading
```bash
# Check nginx status
sudo systemctl status nginx

# Test local access
curl -v http://192.168.4.1

# Check firewall
sudo ufw status
```

#### WiFi Connection Fails
```bash
# Check NetworkManager logs
sudo journalctl -u NetworkManager -f

# Test manual connection
sudo nmcli dev wifi connect "SSID" password "password"

# Check interface management
sudo nmcli dev status
```

#### Service Won't Stop
```bash
# Force stop all services
sudo systemctl stop hostapd dnsmasq nginx php*-fpm

# Reset network interface
sudo ip addr flush dev wlan0
sudo nmcli dev set wlan0 managed yes
```

### Debug Mode
```bash
# Enable debug logging
sudo sed -i 's/#debug/debug/' /etc/wifi-provisioning/hostapd.conf

# Restart with verbose output
sudo systemctl stop wifi-provisioning
sudo /usr/sbin/hostapd -d /etc/wifi-provisioning/hostapd.conf
```

## 📦 Maintenance

### Regular Maintenance
```bash
# Weekly log rotation
sudo logrotate /etc/logrotate.d/wifi-provisioning

# Monthly system updates
sudo apt update && sudo apt upgrade

# Quarterly configuration backup
sudo tar -czf ~/wifi-provisioning-backup.tar.gz /etc/wifi-provisioning
```

### Updates and Patches
```bash
# Update web interface
sudo cp new-files/* /var/www/wifi-setup/

# Update scripts
sudo cp new-scripts/* /etc/wifi-provisioning/scripts/

# Restart services
sudo systemctl restart wifi-provisioning
```

## 🗑️ Uninstallation

### Complete Removal
```bash
# Run uninstall script
./uninstall-wifi-provisioning.sh

# Manual cleanup (if needed)
sudo systemctl stop wifi-provisioning
sudo rm -rf /etc/wifi-provisioning
sudo rm -rf /var/www/wifi-setup
sudo rm -f /etc/systemd/system/wifi-provisioning*
sudo systemctl daemon-reload
```

## 📞 Support

### Log Collection for Support
```bash
# Collect all relevant logs
sudo tar -czf ~/support-logs.tar.gz \
    /var/log/wifi-provisioning/ \
    /etc/wifi-provisioning/ \
    /var/log/nginx/ \
    /var/log/syslog

# System information
sudo dmesg > ~/dmesg.log
sudo lshw -C network > ~/network-hardware.log
```

### Common Support Information
- Ubuntu/Debian version: `lsb_release -a`
- WiFi hardware: `lshw -C network`
- Kernel version: `uname -a`
- Service status: `systemctl status wifi-provisioning`
- Network interfaces: `ip link show`

## 🔗 References

- [hostapd Documentation](https://w1.fi/hostapd/)
- [NetworkManager Documentation](https://networkmanager.dev/)
- [nginx Configuration Guide](https://nginx.org/en/docs/)
- [systemd Service Documentation](https://www.freedesktop.org/software/systemd/man/systemd.service.html)

---

*This deployment guide ensures reliable, production-grade WiFi provisioning for headless Ubuntu Server deployments.*