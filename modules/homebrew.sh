#!/bin/bash
# 03-homebrew.sh - Installing Homebrew and packages
set -euo pipefail

# Source helper functions and config
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/modules/_functions.sh"

# Load system configuration
load_system_config

# Error handling
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        error "Homebrew setup failed"
        error "Try manual installation: https://brew.sh"
    fi
}

trap cleanup EXIT
trap 'error "Error on line $LINENO. Exit code: $?"' ERR

# Pre-flight checks
if ! command -v curl &>/dev/null; then
    error "curl is not installed. Cannot download Homebrew."
    exit 1
fi

if ! check_internet; then
    error "No internet connection. Check your network settings."
    exit 1
fi

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "                         Homebrew Setup                         "
echo "════════════════════════════════════════════════════════════════"
echo ""

# ════════════════════════════════════════════════════════════════
# STEP 1: Install Homebrew
# ════════════════════════════════════════════════════════════════
title "Installing Homebrew"

if command_exists brew; then
    success "Homebrew already installed"
    info "Version: $(brew --version | head -1)"
    info "Prefix: $(brew --prefix)"

    # Update Homebrew
    step "Updating Homebrew..."
    brew update
    success "Homebrew updated"
else
    warning "Homebrew not installed"
    info "Starting Homebrew installation..."

    # Install Homebrew (official installation method from https://brew.sh)
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Add Homebrew to PATH (check for duplicates first)
    if is_apple_silicon; then
        # Apple Silicon
        BREW_SHELLENV="eval \"\$(/opt/homebrew/bin/brew shellenv)\""
        if ! grep -Fxq "$BREW_SHELLENV" ~/.zprofile 2>/dev/null; then
            echo "$BREW_SHELLENV" >> ~/.zprofile
            info "Added Homebrew to ~/.zprofile"
        fi
        eval "$(/opt/homebrew/bin/brew shellenv)"
    else
        # Intel
        BREW_SHELLENV="eval \"\$(/usr/local/bin/brew shellenv)\""
        if ! grep -Fxq "$BREW_SHELLENV" ~/.zprofile 2>/dev/null; then
            echo "$BREW_SHELLENV" >> ~/.zprofile
            info "Added Homebrew to ~/.zprofile"
        fi
        eval "$(/usr/local/bin/brew shellenv)"
    fi

    if command_exists brew; then
        success "Homebrew installed successfully!"
        info "Version: $(brew --version | head -1)"
    else
        error "Error installing Homebrew"
        exit 1
    fi
fi

# ════════════════════════════════════════════════════════════════
# STEP 2: Install Essential Taps
# ════════════════════════════════════════════════════════════════
title "Installing essential taps"

taps=(
    "homebrew/bundle"
    "homebrew/services"
    "homebrew/cask-fonts"
    "homebrew/cask-versions"
)

for tap in "${taps[@]}"; do
    if brew tap | grep -q "^$tap\$"; then
        info "✓ Tap already added: $tap"
    else
        step "Adding tap: $tap"
        brew tap "$tap"
        success "Tap added: $tap"
    fi
done

# ════════════════════════════════════════════════════════════════
# STEP 3: Install mas (Mac App Store CLI)
# ════════════════════════════════════════════════════════════════
title "Installing Mac App Store CLI"

if ! command_exists mas; then
    step "Installing mas..."
    brew install mas
    success "mas installed"
else
    success "mas already installed"
    info "Version: $(mas version)"
fi

# Check if signed in to App Store
if ! mas account &>/dev/null; then
    warning "⚠️  You are not signed in to Mac App Store"
    echo ""
    info "Please follow these steps:"
    info "1. Open App Store application"
    info "2. Sign in to your Apple ID"
    info "3. Wait for authentication to complete"
    echo ""
    info "Press Enter when ready to continue..."
    read -r

    # Check again after user action
    if ! mas account &>/dev/null; then
        error "Still not signed in to Mac App Store"
        error "MAS apps installation will be skipped"
        error "You can run script 06-apps.sh later to install MAS apps"
    else
        success "Signed in to Mac App Store: $(mas account)"
    fi
else
    success "Signed in to Mac App Store: $(mas account)"
fi

# ════════════════════════════════════════════════════════════════
# STEP 4: Install Packages via Brewfile
# ════════════════════════════════════════════════════════════════
title "Installing packages from Brewfile"

BREWFILE="$SCRIPT_DIR/Brewfile"

if [[ ! -f "$BREWFILE" ]]; then
    error "Brewfile not found at: $BREWFILE"
    exit 1
fi

info "Using Brewfile: $BREWFILE"
echo ""

# Show what will be installed
step "Analyzing Brewfile..."
brew_count=$(grep -c '^brew ' "$BREWFILE" || true)
cask_count=$(grep -c '^cask ' "$BREWFILE" || true)
mas_count=$(grep -c '^mas ' "$BREWFILE" || true)

info "📦 Packages to install:"
info "   • Formulas: $brew_count"
info "   • Casks: $cask_count"
info "   • Mac App Store: $mas_count"
echo ""

# Ask for confirmation
warning "This will install all packages from Brewfile"
info "Installation may take 30-60 minutes depending on internet speed"
echo ""
read -p "$(echo -e "${YELLOW}Continue with installation? [Y/n]:${NC} ")" -n 1 -r
echo

# Handle input: empty or 'Y/y' = yes, 'N/n' = no
REPLY_LOWER=$(echo "${REPLY}" | tr '[:upper:]' '[:lower:]')
if [[ "$REPLY_LOWER" == "n" ]]; then
    info "Installation cancelled"
    exit 0
fi

# Install packages using brew bundle
step "Running brew bundle install..."
echo ""

if brew bundle install --file="$BREWFILE" --verbose; then
    echo ""
    success "✅ All packages installed successfully!"
else
    echo ""
    warning "⚠️  Some packages failed to install"
    info "Check the output above for details"
    info "You can run 'brew bundle install --file=$BREWFILE' manually later"
fi

# ════════════════════════════════════════════════════════════════
# STEP 5: Cleanup
# ════════════════════════════════════════════════════════════════
title "Cleanup"

step "Running brew cleanup..."
brew cleanup

# ════════════════════════════════════════════════════════════════
# Summary
# ════════════════════════════════════════════════════════════════
echo ""
echo "════════════════════════════════════════════════════════════════"
success "Homebrew setup completed!"
echo "════════════════════════════════════════════════════════════════"
echo ""

info "📊 Installation Summary:"
info "   • Homebrew: $(brew --version | head -1)"
info "   • Formulas installed: $(brew list --formula | wc -l | tr -d ' ')"
info "   • Casks installed: $(brew list --cask | wc -l | tr -d ' ')"
if command_exists mas; then
    info "   • MAS apps installed: $(mas list | wc -l | tr -d ' ')"
fi
echo ""

# ════════════════════════════════════════════════════════════════
# STEP 6: Upgrade Package Managers
# ════════════════════════════════════════════════════════════════
title "Upgrading package managers"

# Upgrade pip (Python package manager)
if command_exists pip3; then
    step "Upgrading pip, setuptools, and wheel..."
    if pip3 install --user --upgrade pip setuptools wheel 2>/dev/null; then
        success "Python package tools upgraded"
    else
        warning "Failed to upgrade pip (not critical)"
    fi
fi

# Upgrade npm (Node.js package manager)
if command_exists npm; then
    step "Upgrading npm to latest version..."
    if npm install -g npm@latest 2>/dev/null; then
        success "npm upgraded to $(npm --version)"
    else
        warning "Failed to upgrade npm (not critical)"
    fi
fi

echo ""

info "💡 Useful commands:"
info "   brew bundle dump          - Create Brewfile from installed packages"
info "   brew bundle install       - Install from Brewfile"
info "   brew bundle cleanup       - Uninstall packages not in Brewfile"
info "   brew bundle check         - Check if Brewfile packages are installed"
info "   brew list                 - List all installed packages"
info "   brew outdated             - Show outdated packages"
info "   brew upgrade              - Upgrade all packages"
echo ""
