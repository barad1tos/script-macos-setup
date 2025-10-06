#!/bin/bash
# 04-1password.sh - Install and configure 1Password with SSH
set -euo pipefail

# Source helper functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/modules/_functions.sh"

# Load system configuration
load_system_config

# Error handling
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        error "1Password setup failed"
        warning "SSH may not work correctly without 1Password SSH agent"
        info "You can configure it manually later in 1Password settings"
    fi
}

trap cleanup EXIT
trap 'error "Error on line $LINENO. Exit code: $?"' ERR

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "                    1Password & SSH Setup                       "
echo "════════════════════════════════════════════════════════════════"
echo ""

# ════════════════════════════════════════════════════════════════
# STEP 1: Install 1Password
# ════════════════════════════════════════════════════════════════
title "Installing 1Password"

# Check if 1Password is installed (via brew or manually)
if app_in_brew "1password" || [[ -d "/Applications/1Password.app" ]]; then
    success "1Password already installed"

    # If installed manually, offer to manage via brew
    if [[ -d "/Applications/1Password.app" ]] && ! app_in_brew "1password"; then
        info "1Password installed manually (not via Homebrew)"
        info "Consider managing it via Homebrew for easier updates"
    fi
else
    step "Installing 1Password..."
    brew install --cask 1password
    success "1Password installed"
fi

# Install 1Password CLI
if app_in_brew "1password-cli" || command_exists op; then
    success "1Password CLI already installed"
    info "Version: $(op --version 2>/dev/null || echo 'unknown')"
else
    step "Installing 1Password CLI..."
    brew install 1password-cli
    success "1Password CLI installed"
fi

# ════════════════════════════════════════════════════════════════
# STEP 2: Ensure 1Password is running
# ════════════════════════════════════════════════════════════════
title "Checking 1Password application"

if pgrep -x "1Password" > /dev/null; then
    success "1Password is running"
else
    warning "1Password is not running"
    info "Starting 1Password..."

    if [[ -d "/Applications/1Password.app" ]]; then
        open -a "1Password"

        # Wait for 1Password to start with polling (max 15 seconds)
        TIMEOUT=15
        ELAPSED=0
        info "Waiting for 1Password to start (timeout: ${TIMEOUT}s)..."

        while [[ $ELAPSED -lt $TIMEOUT ]]; do
            if pgrep -x "1Password" > /dev/null; then
                success "1Password started (took ${ELAPSED}s)"
                break
            fi
            sleep 1
            ELAPSED=$((ELAPSED + 1))
        done

        # Verify it actually started
        if ! pgrep -x "1Password" > /dev/null; then
            error "1Password failed to start after ${TIMEOUT} seconds"
            error "This might happen if:"
            info "  • Your Mac is under heavy load"
            info "  • 1Password needs to update"
            info "  • There are permission issues"
            echo ""
            error "Please start 1Password manually and run this script again"
            exit 1
        fi
    else
        error "1Password.app not found in /Applications"
        exit 1
    fi
fi

# ════════════════════════════════════════════════════════════════
# STEP 3: Configure SSH for 1Password Agent
# ════════════════════════════════════════════════════════════════
title "Configuring SSH for the 1Password Agent"

SSH_CONFIG="$HOME/.ssh/config"
SSH_DIR="$HOME/.ssh"

# 1Password SSH agent socket path (same for Intel and Apple Silicon)
AGENT_SOCK="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"

# Verify socket exists (1Password must be running and SSH agent enabled)
if [[ ! -S "$AGENT_SOCK" ]]; then
    warning "1Password SSH agent socket not found"
    warning "Expected location: $AGENT_SOCK"
    info "This usually means SSH agent is not enabled in 1Password"
    info "We'll configure SSH config anyway, but you'll need to enable it manually"
fi

# Create .ssh directory if it doesn't exist
if [[ ! -d "$SSH_DIR" ]]; then
    step "Creating ~/.ssh directory"
    mkdir -p "$SSH_DIR"
    chmod 700 "$SSH_DIR"
    success "Created ~/.ssh directory"
fi

# Check if SSH config already has correct 1Password agent configuration
EXPECTED_CONFIG="IdentityAgent \"$AGENT_SOCK\""
CONFIG_MARKER="# 1Password SSH Agent (added by setup script)"

if [[ -f "$SSH_CONFIG" ]] && grep -Fq "$EXPECTED_CONFIG" "$SSH_CONFIG"; then
    success "SSH already configured correctly for 1Password"
elif [[ -f "$SSH_CONFIG" ]] && grep -Fq "$CONFIG_MARKER" "$SSH_CONFIG"; then
    success "1Password SSH config block already exists"
    info "Configuration block found in: $SSH_CONFIG"
else
    step "Updating SSH config for 1Password Agent"

    # Backup existing config
    if [[ -f "$SSH_CONFIG" ]]; then
        backup_file "$SSH_CONFIG"

        # Check if there's an old/incorrect 1Password configuration
        if grep -q "IdentityAgent.*1password" "$SSH_CONFIG"; then
            warning "Found old 1Password configuration in SSH config"
            info "Old configuration will remain but new one will take precedence"
        fi
    fi

    # Add 1Password SSH agent configuration
    # Using EOF without quotes to allow variable expansion
    cat >> "$SSH_CONFIG" <<EOF

$CONFIG_MARKER
Host *
  IdentityAgent "$AGENT_SOCK"
  UseKeychain no
  AddKeysToAgent no

EOF

    chmod 600 "$SSH_CONFIG"
    success "SSH config updated with correct path"
    info "Configuration added to: $SSH_CONFIG"
fi

# ════════════════════════════════════════════════════════════════
# STEP 4: User instructions for 1Password setup
# ════════════════════════════════════════════════════════════════
echo ""
warning "════════════════════════════════════════════════════════════"
warning "         IMPORTANT: Manual steps to finish configuration"
warning "════════════════════════════════════════════════════════════"
echo ""
info "1. Open 1Password (should already be running)"
info "2. Sign in to your account or create a new one"
info "3. Go to Settings → Developer"
info "4. Enable the following options:"
info "   • Use the SSH agent"
info "   • Authorize connections from CLI"
info "5. Add your SSH keys to 1Password if not already stored"
echo ""
warning "Press Enter after completing these steps to continue..."
read -r

# ════════════════════════════════════════════════════════════════
# STEP 5: Test SSH agent connection
# ════════════════════════════════════════════════════════════════
title "Testing SSH agent connection"

# Test SSH agent and capture exit code properly
verify_ssh_agent
SSH_EXIT=$?

if [[ $SSH_EXIT -eq 0 ]]; then
    success "SSH agent is working!"

    # Count actual keys (exclude "no identities" message)
    KEY_OUTPUT=$(ssh-add -l 2>/dev/null)
    if echo "$KEY_OUTPUT" | grep -q "no identities"; then
        KEY_COUNT=0
    else
        KEY_COUNT=$(echo "$KEY_OUTPUT" | wc -l | tr -d ' ')
    fi

    info "SSH keys loaded: $KEY_COUNT"

    # Show loaded keys if any
    if [[ $KEY_COUNT -gt 0 ]]; then
        echo ""
        info "Loaded keys:"
        echo "$KEY_OUTPUT" | while read -r line; do
            info "  • $line"
        done
    fi
elif [[ $SSH_EXIT -eq 1 ]]; then
    warning "SSH agent is running but no keys are loaded"
    echo ""
    info "To add SSH keys to 1Password:"
    info "  1. Click 1Password icon in menu bar"
    info "  2. Go to Settings → Developer"
    info "  3. Click 'Import SSH Key' or add manually"
    info "  4. Restart your terminal after adding keys"
else
    error "Cannot connect to SSH agent"
    echo ""
    warning "Troubleshooting steps:"
    info "  1. Verify 1Password Settings → Developer"
    info "  2. Ensure 'Use the SSH agent' is enabled"
    info "  3. Check socket exists: ls -la \"$AGENT_SOCK\""
    info "  4. Try restarting 1Password"
    info "  5. Restart your terminal"
    echo ""
    info "Current socket path in SSH config:"
    info "  $AGENT_SOCK"
fi

# ════════════════════════════════════════════════════════════════
# STEP 6: Test 1Password CLI
# ════════════════════════════════════════════════════════════════
title "Testing 1Password CLI"

if command_exists op; then
    step "Checking 1Password CLI connection..."

    # Capture both stdout and stderr to show actual error
    if OP_OUTPUT=$(op account list 2>&1); then
        success "1Password CLI is connected and authorized"

        # Show account info
        ACCOUNT_INFO=$(echo "$OP_OUTPUT" | head -2 | tail -1)
        if [[ -n "$ACCOUNT_INFO" ]]; then
            info "Account: $ACCOUNT_INFO"
        fi
    else
        warning "1Password CLI connection failed"
        echo ""

        # Show actual error details (first 10 lines)
        error "Error details:"
        echo "$OP_OUTPUT" | head -10 | while read -r line; do
            info "  $line"
        done
        echo ""

        info "Common solutions:"
        info "  • Not signed in:"
        info "    → Run: eval \$(op signin)"
        info "  • Network issues:"
        info "    → Check internet connection"
        info "    → Verify 1Password service status"
        info "  • Permission issues:"
        info "    → Try: Settings → Developer → Authorize CLI"
        echo ""
        info "Useful commands after fixing:"
        info "  op account list     - List accounts"
        info "  op item list        - List items"
        info "  op read <ref>       - Read secret"
    fi
else
    warning "1Password CLI (op) not found in PATH"
    info "Try restarting your terminal or running: brew install 1password-cli"
fi

# ════════════════════════════════════════════════════════════════
# Summary
# ════════════════════════════════════════════════════════════════
echo ""
echo "════════════════════════════════════════════════════════════════"
success "1Password and SSH setup complete!"
echo "════════════════════════════════════════════════════════════════"
echo ""

info "📝 Configuration summary:"
info "  • 1Password: $(pgrep -x "1Password" > /dev/null && echo "Running ✓" || echo "Not running ✗")"
info "  • SSH agent socket: $AGENT_SOCK"
info "  • SSH config: $SSH_CONFIG"
info "  • 1Password CLI: $(command_exists op && echo "Installed ✓" || echo "Not found ✗")"
echo ""

info "💡 Next steps:"
info "  • Restart your terminal to apply SSH config changes"
info "  • Test SSH: ssh -T git@github.com"
info "  • Test op CLI: op account list"
echo ""
