#!/bin/bash

# NiPux Setup Verification Script
# Ensures the repository is ready for deployment

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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "NiPux Setup Verification"
echo "========================"
echo

errors=0
warnings=0

# Check main installer scripts
log_info "Checking main installer scripts..."

required_scripts=(
    "install.sh"
    "setup-bulletproof.sh" 
    "setup.sh"
    "diagnose-wifi.sh"
    "setup-wifi-provisioning.sh"
    "install-dependencies.sh"
)

for script in "${required_scripts[@]}"; do
    if [[ -f "$SCRIPT_DIR/$script" && -x "$SCRIPT_DIR/$script" ]]; then
        log_success "Found and executable: $script"
    elif [[ -f "$SCRIPT_DIR/$script" ]]; then
        log_warning "Found but not executable: $script"
        chmod +x "$SCRIPT_DIR/$script"
        log_info "Made executable: $script"
    else
        log_error "Missing: $script"
        ((errors++))
    fi
done

# Check documentation
log_info "Checking documentation..."
docs=("README.md" "DEPLOYMENT.md")

for doc in "${docs[@]}"; do
    if [[ -f "$SCRIPT_DIR/$doc" ]]; then
        log_success "Found: $doc"
    else
        log_warning "Missing: $doc"
        ((warnings++))
    fi
done

# Check offline packages
log_info "Checking offline packages..."
if [[ -d "$SCRIPT_DIR/offline-packages" ]]; then
    log_success "Found: offline-packages directory"
    if [[ -f "$SCRIPT_DIR/offline-packages/install-offline-packages.sh" ]]; then
        log_success "Found: offline package installer"
    else
        log_warning "Missing: offline package installer"
        ((warnings++))
    fi
else
    log_warning "Missing: offline-packages directory"
    ((warnings++))
fi

if [[ -d "$SCRIPT_DIR/offline-deps" ]]; then
    log_success "Found: offline-deps directory"
else
    log_warning "Missing: offline-deps directory"
    ((warnings++))
fi

# Check script syntax
log_info "Checking script syntax..."
for script in "$SCRIPT_DIR"/*.sh; do
    if [[ -f "$script" ]]; then
        if bash -n "$script" 2>/dev/null; then
            log_success "Syntax OK: $(basename "$script")"
        else
            log_error "Syntax error: $(basename "$script")"
            ((errors++))
        fi
    fi
done

# Summary
echo
echo "Verification Summary:"
echo "===================="
log_info "Errors: $errors"
log_info "Warnings: $warnings"

if [[ $errors -eq 0 ]]; then
    echo
    log_success "🎉 Repository is ready for deployment!"
    echo
    echo -e "${GREEN}Quick Start Command:${NC}"
    echo -e "${YELLOW}./install.sh${NC}"
    echo
    echo -e "${GREEN}Bulletproof Command:${NC}"
    echo -e "${YELLOW}./setup-bulletproof.sh${NC}"
    echo
    echo -e "${GREEN}Diagnostic Command:${NC}"
    echo -e "${YELLOW}./diagnose-wifi.sh${NC}"
else
    echo
    log_error "❌ Repository has $errors critical issues that need to be fixed"
    exit 1
fi

if [[ $warnings -gt 0 ]]; then
    echo
    log_warning "⚠️  $warnings optional components are missing but system will work"
fi