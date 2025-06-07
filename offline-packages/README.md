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
