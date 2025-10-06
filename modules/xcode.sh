#!/bin/bash
# 02-xcode.sh - Installing Xcode Command Line Tools
set -euo pipefail

# Source helper functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/modules/_functions.sh"

# Load system configuration
load_system_config

# Error handling
cleanup() {
    local exit_code=$?
    # Clean up temporary files
    rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress 2>/dev/null || true
    if [[ $exit_code -ne 0 ]]; then
        error "Xcode installation failed. Please try running manually:"
        error "xcode-select --install"
    fi
}

trap cleanup EXIT
trap 'error "Error on line $LINENO. Exit code: $?"' ERR

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "                    Xcode Command Line Tools                    "
echo "════════════════════════════════════════════════════════════════"
echo ""

# Check if Xcode CLI tools are installed
if xcode-select -p &>/dev/null; then
    XCODE_PATH=$(xcode-select -p)
    success "Xcode Command Line Tools already installed"
    info "Path: $XCODE_PATH"

    # Check version
    if command -v xcodebuild &>/dev/null; then
        XCODE_VERSION=$(xcodebuild -version | head -1)
        info "Version: $XCODE_VERSION"
    fi
else
    warning "Xcode Command Line Tools not installed"
    info "Starting installation..."

    # Trigger the installation
    touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress

    # Find the CLI tools package
    PROD=$(softwareupdate -l | grep "\*.*Command Line Tools" | tail -1 | sed 's/^[[:space:]]*\*//')

    if [[ -n "$PROD" ]]; then
        info "Installing: $PROD"
        softwareupdate -i "$PROD" --verbose

        rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress

        if xcode-select -p &>/dev/null; then
            success "Xcode Command Line Tools installed successfully!"
        else
            error "Error installing Xcode Command Line Tools"
            exit 1
        fi
    else
        # Alternative method
        info "Using alternative installation method..."
        xcode-select --install

        warning "Follow the instructions in the installation window"
        warning "Press Enter when installation is complete..."
        read -r

        if xcode-select -p &>/dev/null; then
            success "Xcode Command Line Tools installed successfully!"
        else
            error "Error installing Xcode Command Line Tools"
            exit 1
        fi
    fi
fi

# Accept license if needed
if ! sudo xcodebuild -license status &>/dev/null; then
    warning "Need to accept Xcode license"
    sudo xcodebuild -license accept
    success "License accepted"
fi

echo ""
success "Xcode Command Line Tools ready to use!"
echo ""