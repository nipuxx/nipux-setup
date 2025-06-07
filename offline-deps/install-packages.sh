#!/bin/bash
# Install offline packages

echo "Installing offline packages..."
sudo dpkg -i *.deb 2>/dev/null || true
sudo apt-get install -f -y 2>/dev/null || true
echo "Offline packages installed!"
