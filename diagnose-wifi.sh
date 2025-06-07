#!/bin/bash

# WiFi Hardware Diagnostic Script
# Helps identify and troubleshoot wireless hardware issues

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

echo "WiFi Hardware Diagnostic Tool"
echo "============================="
echo

# Check if running as root
if [[ $EUID -eq 0 ]]; then
    SUDO_CMD=""
else
    SUDO_CMD="sudo"
fi

# 1. Check PCI devices for wireless hardware
log_info "Checking PCI devices for wireless hardware..."
if lspci | grep -i "network\|wireless\|wifi"; then
    log_success "Found network hardware in PCI devices:"
    lspci | grep -i "network\|wireless\|wifi"
else
    log_warning "No wireless hardware found in PCI devices"
fi
echo

# 2. Check USB devices for wireless hardware  
log_info "Checking USB devices for wireless hardware..."
if lsusb | grep -i "wireless\|wifi\|802.11"; then
    log_success "Found wireless hardware in USB devices:"
    lsusb | grep -i "wireless\|wifi\|802.11"
else
    log_warning "No wireless hardware found in USB devices"
fi
echo

# 3. Check kernel messages for wireless
log_info "Checking kernel messages for wireless references..."
if dmesg | grep -i "wireless\|wifi\|802.11" | head -5; then
    log_success "Found wireless references in kernel messages"
else
    log_warning "No wireless references in kernel messages"
fi
echo

# 4. Check network interfaces
log_info "Checking network interfaces..."
echo "All network interfaces:"
ip link show
echo

log_info "Looking for wireless interfaces specifically..."
if ip link show | grep -E "wlan|wlp|wifi"; then
    log_success "Found potential wireless interfaces:"
    ip link show | grep -E "wlan|wlp|wifi"
else
    log_warning "No obvious wireless interfaces found"
fi
echo

# 5. Check /sys/class/net for wireless capabilities
log_info "Checking /sys/class/net for wireless capabilities..."
wireless_found=false
for iface in $(ls /sys/class/net/ 2>/dev/null); do
    if [[ -d "/sys/class/net/$iface/wireless" ]]; then
        log_success "Interface $iface has wireless capabilities"
        wireless_found=true
    fi
done

if [[ "$wireless_found" == "false" ]]; then
    log_warning "No interfaces with wireless capabilities found in /sys/class/net"
fi
echo

# 6. Check if iw command works
log_info "Testing iw command..."
if command -v iw >/dev/null 2>&1; then
    log_success "iw command is available"
    if iw dev 2>/dev/null; then
        log_success "iw dev command works - wireless interfaces detected"
    else
        log_warning "iw dev returned no results"
    fi
else
    log_warning "iw command not found - installing wireless tools may help"
fi
echo

# 7. Check wireless kernel modules
log_info "Checking loaded wireless kernel modules..."
if lsmod | grep -E "cfg80211|mac80211|wireless"; then
    log_success "Found wireless kernel modules:"
    lsmod | grep -E "cfg80211|mac80211|wireless"
else
    log_warning "No obvious wireless kernel modules loaded"
fi
echo

# 8. Check NetworkManager status
log_info "Checking NetworkManager status..."
if systemctl is-active --quiet NetworkManager 2>/dev/null; then
    log_success "NetworkManager is running"
    if command -v nmcli >/dev/null 2>&1; then
        log_info "NetworkManager device status:"
        nmcli dev status 2>/dev/null || log_warning "Could not get NetworkManager device status"
    fi
else
    log_warning "NetworkManager is not running"
fi
echo

# 9. Detailed hardware information
log_info "Detailed network hardware information:"
if command -v lshw >/dev/null 2>&1; then
    $SUDO_CMD lshw -C network 2>/dev/null || log_warning "Could not get detailed hardware info"
else
    log_warning "lshw command not available for detailed hardware info"
fi
echo

# 10. Suggestions
echo "🔧 Troubleshooting Suggestions:"
echo "==============================="

if ! lspci | grep -i "network\|wireless\|wifi" >/dev/null && ! lsusb | grep -i "wireless\|wifi" >/dev/null; then
    log_error "No wireless hardware detected"
    echo "• This system may not have wireless hardware"
    echo "• Consider adding a USB WiFi adapter"
    echo "• Check if wireless is disabled in BIOS/UEFI"
else
    log_info "Wireless hardware detected but not working properly"
    echo "• Try installing wireless drivers: sudo apt install linux-firmware"
    echo "• Install wireless tools: sudo apt install wireless-tools wpasupplicant iw"
    echo "• Load wireless modules: sudo modprobe cfg80211 && sudo modprobe mac80211"
    echo "• Bring up interfaces: sudo ip link set <interface> up"
    echo "• Check if rfkill is blocking: sudo rfkill list"
fi

echo
echo "💡 Quick Fix Commands:"
echo "====================="
echo "# Install essential wireless packages:"
echo "sudo apt update && sudo apt install -y linux-firmware wireless-tools wpasupplicant iw rfkill hostapd dnsmasq"
echo
echo "# Load wireless kernel modules:"
echo "sudo modprobe cfg80211"
echo "sudo modprobe mac80211"
echo "# Try specific drivers:"
echo "sudo modprobe ath9k"
echo "sudo modprobe iwlwifi"
echo "sudo modprobe rt2800pci"
echo "sudo modprobe brcmfmac"
echo
echo "# Check and unblock wireless:"
echo "sudo rfkill list"
echo "sudo rfkill unblock wifi"
echo "sudo rfkill unblock all"
echo
echo "# Try to bring up any wireless interfaces:"
echo "for iface in \$(ls /sys/class/net/); do"
echo "  if [[ -d \"/sys/class/net/\$iface/wireless\" ]]; then"
echo "    echo \"Bringing up \$iface\""
echo "    sudo ip link set \"\$iface\" up"
echo "    sudo iw dev \"\$iface\" scan | head -10"
echo "  fi"
echo "done"

echo
echo "🔥 BULLETPROOF FIX:"
echo "=================="
echo "# If nothing else works, run the bulletproof setup:"
echo "./setup-bulletproof.sh"