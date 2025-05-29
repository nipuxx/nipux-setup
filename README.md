# WiFi Connect Setup Script

A comprehensive bash script that automates the installation and configuration of [balena wifi-connect](https://github.com/balena-os/wifi-connect) for plug-and-play WiFi provisioning on Ubuntu/Debian systems.

## 🚀 Quick Start

```bash
# Download and run the setup script
./setup-wifi-connect.sh
```

That's it! The script will handle everything automatically.

## 📋 What This Script Does

1. **Installs Dependencies**: NetworkManager, dnsmasq-base, and other required packages
2. **Downloads wifi-connect**: Fetches the latest pre-built binary (v5.0.3)
3. **Creates System Service**: Sets up a systemd service that starts automatically
4. **Configures Network Management**: Creates cleanup scripts and NetworkManager hooks
5. **Provides Easy Uninstall**: Generates an uninstall script for easy removal

## 🔧 How It Works

### Automatic WiFi Provisioning Flow

1. **Device boots** without WiFi connection
2. **Hotspot activates** automatically with SSID: `{hostname}-setup`
3. **User connects** to the hotspot with any device (phone, laptop, etc.)
4. **Captive portal** appears automatically
5. **User selects** their WiFi network and enters password
6. **Device connects** to the real WiFi and hotspot disappears
7. **System remembers** the WiFi for future connections

### Technical Details

- **Hotspot SSID**: `{your-hostname}-setup` (e.g., `raspberrypi-setup`)
- **Portal IP**: `192.168.4.1`
- **Service Type**: systemd service with automatic restart
- **Network Detection**: Uses NetworkManager connection monitoring
- **Cleanup**: Automatic removal of connection flags when network drops

## 📱 User Experience

### For End Users (Device Setup)
1. Look for WiFi network named `{hostname}-setup`
2. Connect to it (no password required)
3. Web page should open automatically (captive portal)
4. If not, navigate to `http://192.168.4.1` in your browser
5. Select your WiFi network from the list
6. Enter your WiFi password
7. Click "Connect"
8. Device will reboot networking and connect to your WiFi

### For Administrators
```bash
# Check service status
sudo systemctl status wifi-connect

# View real-time logs
sudo journalctl -u wifi-connect -f

# Manually start the hotspot
sudo systemctl start wifi-connect

# Stop the hotspot
sudo systemctl stop wifi-connect

# Force reset (remove connection memory)
sudo rm -f /var/run/wifi-connected
sudo systemctl restart wifi-connect
```

## 🛠 System Requirements

- **OS**: Ubuntu 18.04+ or Debian 10+
- **Hardware**: Device with WiFi capability
- **Network**: Internet connection for initial setup
- **Privileges**: sudo access
- **Dependencies**: Automatically installed by the script

## 📊 Monitoring and Troubleshooting

### Check Status
```bash
# Service status
sudo systemctl status wifi-connect

# View logs
sudo journalctl -u wifi-connect --no-pager

# Check NetworkManager status
sudo systemctl status NetworkManager

# List network interfaces
ip link show
```

### Common Issues

#### Hotspot doesn't appear
```bash
# Check if service is running
sudo systemctl status wifi-connect

# Check for existing connections
nmcli connection show

# Manually remove connection flag
sudo rm -f /var/run/wifi-connected
sudo systemctl restart wifi-connect
```

#### Captive portal doesn't load
```bash
# Check if the service is bound to the correct interface
sudo netstat -tulpn | grep :80

# Manually navigate to the portal
# Open browser and go to: http://192.168.4.1
```

#### Device won't connect to selected WiFi
```bash
# Check NetworkManager logs
sudo journalctl -u NetworkManager -f

# List saved connections
nmcli connection show

# Test manual connection
nmcli device wifi connect "SSID" password "password"
```

## 🗑 Uninstallation

The setup script creates an uninstall script automatically:

```bash
./uninstall-wifi-connect.sh
```

### Manual Uninstall
```bash
# Stop and disable service
sudo systemctl stop wifi-connect.service
sudo systemctl disable wifi-connect.service

# Remove files
sudo rm -f /etc/systemd/system/wifi-connect.service
sudo rm -f /usr/local/bin/wifi-connect
sudo rm -f /usr/local/bin/wifi-connect-cleanup
sudo rm -f /etc/NetworkManager/dispatcher.d/99-wifi-connect
sudo rm -f /var/run/wifi-connected

# Reload systemd
sudo systemctl daemon-reload
```

## 🔒 Security Considerations

- **Hotspot Security**: The setup hotspot is intentionally unencrypted for easy access
- **Portal Security**: The captive portal runs on HTTP (port 80) for compatibility
- **Network Isolation**: The hotspot creates an isolated network segment
- **Automatic Shutdown**: The hotspot shuts down immediately after successful configuration
- **No Persistence**: WiFi credentials are handled by NetworkManager, not stored by wifi-connect

## 🎯 Use Cases

- **IoT Device Setup**: Easy WiFi provisioning for headless devices
- **Raspberry Pi Projects**: Plug-and-play WiFi setup for Pi-based projects
- **Embedded Systems**: Simple network configuration for embedded Linux devices
- **Field Deployment**: Easy network setup without keyboard/display
- **Customer Premises**: User-friendly WiFi setup for deployed devices

## 📋 File Structure

After installation, the following files are created:

```
/usr/local/bin/wifi-connect              # Main binary
/usr/local/bin/wifi-connect-cleanup      # Network cleanup script
/etc/systemd/system/wifi-connect.service # Systemd service
/etc/NetworkManager/dispatcher.d/99-wifi-connect # NM hook
/var/run/wifi-connected                  # Connection flag (when connected)
./uninstall-wifi-connect.sh             # Uninstall script
```

## 🤝 Contributing

This setup script is designed to be:
- **Idempotent**: Safe to run multiple times
- **Robust**: Comprehensive error checking and validation
- **User-friendly**: Clear feedback and colored output
- **Maintainable**: Well-documented and modular code

Feel free to submit issues or improvements!

## 📄 License

This setup script is provided as-is. The wifi-connect binary is licensed under Apache 2.0 by Balena.

## 🔗 References

- [balena wifi-connect GitHub](https://github.com/balena-os/wifi-connect)
- [NetworkManager Documentation](https://networkmanager.dev/)
- [systemd Service Documentation](https://www.freedesktop.org/software/systemd/man/systemd.service.html) 