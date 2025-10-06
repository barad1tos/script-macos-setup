#!/bin/bash
# 01-preflight.sh - Initial system check
set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Source functions if available
if [[ -f "$SCRIPT_DIR/modules/_functions.sh" ]]; then
    # shellcheck source=modules/_functions.sh
    source "$SCRIPT_DIR/modules/_functions.sh"
else
    # Fallback definitions
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'

    info() { echo -e "${BLUE}[INFO]${NC} $1"; }
    success() { echo -e "${GREEN}[✓]${NC} $1"; }
    warning() { echo -e "${YELLOW}[⚠]${NC} $1"; }
    error() { echo -e "${RED}[✗]${NC} $1" >&2; }
    step() { echo -e "${BLUE}[→]${NC} $1"; }
fi

# Sudo keepalive PID tracking
SUDO_KEEPALIVE_PID=""

# Start sudo keepalive with PID tracking
start_sudo_keepalive() {
    while true; do
        sudo -n true
        sleep 60
        kill -0 "$$" || exit
    done 2>/dev/null &
    SUDO_KEEPALIVE_PID=$!
    echo "$SUDO_KEEPALIVE_PID" > "/tmp/macos-setup-sudo-$$"
}

# Stop sudo keepalive
stop_sudo_keepalive() {
    if [[ -n "$SUDO_KEEPALIVE_PID" ]] && kill -0 "$SUDO_KEEPALIVE_PID" 2>/dev/null; then
        kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    fi
    rm -f "/tmp/macos-setup-sudo-$$"
}

# Error handling
cleanup() {
    local exit_code=$?
    stop_sudo_keepalive

    if [[ $exit_code -ne 0 ]]; then
        error "Preflight check failed with exit code: $exit_code"
        error "Please fix the issues above and try again"
    fi
}

trap cleanup EXIT
trap 'error "Error on line $LINENO. Exit code: $?"' ERR

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "                    macOS Setup - Preflight Check               "
echo "════════════════════════════════════════════════════════════════"
echo ""

# Check macOS version
info "Checking macOS version..."
MACOS_VERSION=$(sw_vers -productVersion)
MACOS_NAME=$(sw_vers -productName)
info "Found: $MACOS_NAME $MACOS_VERSION"

# Check if running on Apple Silicon or Intel
if [[ $(uname -m) == "arm64" ]]; then
    ARCH="Apple Silicon"
    HOMEBREW_PREFIX="/opt/homebrew"
else
    ARCH="Intel"
    HOMEBREW_PREFIX="/usr/local"
fi
info "Architecture: $ARCH"

# Check system requirements
info "Checking system requirements..."

# Check disk space (need at least 20GB)
AVAILABLE_SPACE=$(df -g / 2>/dev/null | awk 'NR==2 {print $4}')

if [[ -n "$AVAILABLE_SPACE" ]] && [[ "$AVAILABLE_SPACE" -gt 0 ]]; then
    if [[ $AVAILABLE_SPACE -lt 20 ]]; then
        error "Insufficient disk space: ${AVAILABLE_SPACE}GB available (need 20GB+)"
        error "Free up some space and try again"
        exit 1
    else
        success "Disk space: ${AVAILABLE_SPACE}GB available"
    fi
else
    warning "Could not check disk space (df -g failed)"
    warning "Make sure you have at least 20GB free"
    info "You can check manually: df -h /"
fi

# Check battery level (if laptop)
if pmset -g batt | grep -q "Battery"; then
    BATTERY_LEVEL=$(pmset -g batt | grep -Eo "\d+%" | cut -d% -f1)
    IS_PLUGGED_IN=$(pmset -g batt | grep -q "AC Power" && echo "yes" || echo "no")

    if [[ $BATTERY_LEVEL -lt 50 ]] && [[ "$IS_PLUGGED_IN" == "no" ]]; then
        warning "Battery at ${BATTERY_LEVEL}% and not plugged in"
        warning "Setup takes ~60 minutes. Recommended to connect to power"
        echo ""
        read -p "$(echo -e "${YELLOW}Continue anyway? [y/N]:${NC} ")" -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            info "Setup cancelled. Connect to power and try again"
            exit 0
        fi
    else
        success "Power: ${BATTERY_LEVEL}% (${IS_PLUGGED_IN} plugged in)"
    fi
fi

# Check if running as admin
if ! sudo -n true 2>/dev/null; then
    warning "Administrator rights required for some operations"
    info "Requesting password..."
    sudo -v
    start_sudo_keepalive
else
    start_sudo_keepalive
fi

# Detect iCloud Drive directory
info "Detecting iCloud Drive location..."
if ICLOUD_DIR=$(detect_icloud_dir 2>/dev/null); then
    success "iCloud Drive found: $ICLOUD_DIR"
else
    error "iCloud Drive not found!"
    error "Sign in to iCloud and wait for sync to complete"
    exit 1
fi

# Check iCloud sync status
step "Verifying iCloud sync status..."
if check_icloud_sync "$ICLOUD_DIR"; then
    success "iCloud Drive fully synced"
else
    error "iCloud Drive not fully synced yet"
    error "Wait for sync to complete and try again"
    info "You can check sync status in Finder sidebar"
    exit 1
fi

# Check if our repositories exist
SCRIPT_DIR="$ICLOUD_DIR/3. Git/Own/scripts/bash/script-macos-setup"
DOTFILES_DIR="$ICLOUD_DIR/3. Git/Own/dotfiles"

if [[ -d "$SCRIPT_DIR" ]]; then
    success "Found script-macos-setup in iCloud"
else
    error "script-macos-setup not found in iCloud"
    error "Expected at: $SCRIPT_DIR"
    exit 1
fi

if [[ -d "$DOTFILES_DIR" ]]; then
    success "Found dotfiles in iCloud"
else
    warning "dotfiles not found in iCloud - will be cloned from GitHub"
fi

# Check internet connection with multiple endpoints
step "Checking internet connection..."
if check_internet; then
    # Success message already printed by check_internet
    :
else
    error "No internet connection!"
    error "Connect to internet and try again"
    exit 1
fi

# Export variables for other scripts
export MACOS_VERSION
export ARCH
export HOMEBREW_PREFIX
export ICLOUD_DIR
export SCRIPT_DIR
export DOTFILES_DIR

# Ensure config directory exists
mkdir -p "$SCRIPT_DIR/config"

# Save configuration
CONFIG_FILE="$SCRIPT_DIR/config/system.conf"
cat > "$CONFIG_FILE" <<EOF
# System configuration - generated by preflight
MACOS_VERSION="$MACOS_VERSION"
ARCH="$ARCH"
HOMEBREW_PREFIX="$HOMEBREW_PREFIX"
ICLOUD_DIR="$ICLOUD_DIR"
SCRIPT_DIR="$SCRIPT_DIR"
DOTFILES_DIR="$DOTFILES_DIR"
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"
EOF

success "Preflight check completed successfully!"
echo ""
info "Configuration saved to: $CONFIG_FILE"
echo ""
