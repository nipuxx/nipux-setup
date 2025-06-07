#!/bin/bash

# NiPux Installer - Automatic Setup Method Selection
# This script automatically chooses the best installation method

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}NiPux WiFi Provisioning - Auto Installer${NC}"
echo "=========================================="
echo

# Check what we have available
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "$SCRIPT_DIR/setup-bulletproof.sh" ]]; then
    echo -e "${GREEN}✓ Bulletproof installer found${NC}"
    echo "This installer has maximum compatibility and multiple fallbacks"
    echo
    
    read -p "Use bulletproof installer? (recommended) [Y/n]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        use_bulletproof=false
    else
        use_bulletproof=true
    fi
else
    use_bulletproof=false
fi

if [[ "$use_bulletproof" == "true" ]]; then
    echo -e "${BLUE}Running bulletproof installer...${NC}"
    exec bash "$SCRIPT_DIR/setup-bulletproof.sh"
elif [[ -f "$SCRIPT_DIR/setup.sh" ]]; then
    echo -e "${BLUE}Running standard installer...${NC}"
    exec bash "$SCRIPT_DIR/setup.sh"
elif [[ -f "$SCRIPT_DIR/setup-wifi-provisioning.sh" ]]; then
    echo -e "${BLUE}Running WiFi provisioning installer...${NC}"
    exec bash "$SCRIPT_DIR/setup-wifi-provisioning.sh"
else
    echo -e "${YELLOW}No installer scripts found!${NC}"
    echo "Available files:"
    ls -la "$SCRIPT_DIR"/*.sh 2>/dev/null || echo "No .sh files found"
    exit 1
fi