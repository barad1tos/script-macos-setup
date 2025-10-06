#!/bin/bash
# 07-mackup.sh - Configure Mackup for syncing settings
set -euo pipefail

# Source helper functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/modules/_functions.sh"

# Load system configuration
load_system_config

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "                         Mackup Setup                           "
echo "════════════════════════════════════════════════════════════════"
echo ""

# Check if Mackup is installed
if ! command_exists mackup; then
    warning "Mackup is not installed"
    step "Installing Mackup..."

    # Check if Homebrew is installed
    if ! command_exists brew; then
        warning "Homebrew is not installed."
        echo "Please install Homebrew first: https://brew.sh/"
        exit 1
    fi

    brew install mackup
fi

title "Mackup configuration"

# Backup directory in iCloud
MACKUP_DIR="$HOME/Library/Mobile Documents/com~apple~CloudDocs/2. Backup/mackup"

# Create Mackup configuration
step "Creating Mackup configuration"

# Backup existing config if it exists
if [[ -f "$HOME/.mackup.cfg" ]]; then
    backup_file "$HOME/.mackup.cfg"
fi

cat > "$HOME/.mackup.cfg" <<'EOF'
[storage]
engine = icloud
directory = 2. Backup/mackup

# CRITICAL: Exclude sensitive data and dotfiles
[applications_to_ignore]
# Sensitive data (managed by 1Password)
ssh
aws
kubernetes-cli
gcloud-cli

# Managed by dotfiles (Git versioning)
git
zsh
bash
oh-my-zsh
vim
neovim
EOF

success "Configuration created: ~/.mackup.cfg"

# Create custom Mackup configurations for apps without built-in support
title "Creating custom Mackup configurations"

mkdir -p "$HOME/.mackup"

# Note: Most modern apps (Arc, Notion, Slack, Discord, etc.) sync settings via cloud authentication.
# Custom configs are only needed for apps that store settings locally.

step "Creating custom config: Reeder"
if [[ -f "$HOME/.mackup/reeder.cfg" ]]; then
    backup_file "$HOME/.mackup/reeder.cfg"
fi
cat > "$HOME/.mackup/reeder.cfg" <<'EOF'
[application]
name = Reeder

[configuration_files]
Library/Containers/com.reederapp.5.macOS/Data/Library/Preferences/com.reederapp.5.macOS.plist
Library/Preferences/com.reederapp.5.macOS.plist
EOF

step "Creating custom config: Warp"
if [[ -f "$HOME/.mackup/warp.cfg" ]]; then
    backup_file "$HOME/.mackup/warp.cfg"
fi
cat > "$HOME/.mackup/warp.cfg" <<'EOF'
[application]
name = Warp

[configuration_files]
.warp
EOF

step "Creating custom config: Zed"
if [[ -f "$HOME/.mackup/zed.cfg" ]]; then
    backup_file "$HOME/.mackup/zed.cfg"
fi
cat > "$HOME/.mackup/zed.cfg" <<'EOF'
[application]
name = Zed

[configuration_files]
.config/zed
EOF

success "Custom Mackup configurations created in ~/.mackup/"
info "Apps with custom configs: Reeder, Warp, Zed"

# Check if this is a restoration or backup
title "Checking for existing backup"

if [[ -d "$MACKUP_DIR" ]] && find "$MACKUP_DIR" -mindepth 1 -print -quit | grep -q .; then
    info "Found existing backup at: $MACKUP_DIR"

    if confirm "Restore settings from backup?" "y"; then
        step "Restoring settings..."
        mackup restore --force
        success "Settings restored!"
    else
        info "Skipping restore"

        if confirm "Create a new backup of the current settings?" "y"; then
            step "Creating backup..."
            mackup backup --force
            success "Backup created!"
        fi
    fi
else
    info "Backup not found"

    if confirm "Create a backup of the current settings?" "y"; then
        step "Creating initial backup..."

        # Create backup directory if it doesn't exist
        mkdir -p "$MACKUP_DIR"

        mackup backup --force
        success "Backup created at: $MACKUP_DIR"
    fi
fi

# Show Mackup status
echo ""
title "Mackup status"
mackup list || warning "Failed to list Mackup applications"

echo ""
success "Mackup configuration complete!"
info "Backup directory: $MACKUP_DIR"
echo ""
