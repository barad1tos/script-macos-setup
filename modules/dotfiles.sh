#!/bin/bash
# 05-dotfiles.sh - Clone and install dotfiles
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
        error "Dotfiles setup failed"
        warning "Your shell configuration may be incomplete"
        info "Try cloning manually: git clone git@github.com:robluk/dotfiles.git"
    fi
}

trap cleanup EXIT
trap 'error "Error on line $LINENO. Exit code: $?"' ERR

# Pre-flight checks
if ! command -v git &>/dev/null; then
    error "git is not installed. Cannot clone dotfiles."
    exit 1
fi

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "                         Dotfiles Setup                         "
echo "════════════════════════════════════════════════════════════════"
echo ""

# Set dotfiles directory
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/Library/Mobile Documents/com~apple~CloudDocs/3. Git/Own/dotfiles}"

title "Dotfiles check"

# Check if dotfiles already exist
if [[ -d "$DOTFILES_DIR" ]]; then
    success "Dotfiles found at: $DOTFILES_DIR"

    # Check if it's a git repository
    if [[ -d "$DOTFILES_DIR/.git" ]]; then
        step "Updating dotfiles from GitHub..."
        cd "$DOTFILES_DIR"

        # Check for uncommitted changes before pulling
        if ! git diff-index --quiet HEAD -- 2>/dev/null; then
            warning "Dotfiles have uncommitted changes"
            info "Stashing local changes before update..."
            git stash save "Auto-stash before dotfiles update $(date '+%Y-%m-%d %H:%M:%S')"

            # Get current branch and upstream for explicit pull
            CURRENT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null)
            UPSTREAM=$(git for-each-ref --format='%(upstream:short)' "refs/heads/$CURRENT_BRANCH" 2>/dev/null)

            if [[ -z "$UPSTREAM" ]]; then
                error "Current branch '$CURRENT_BRANCH' is not tracking any remote branch"
                info "Cannot update automatically - please set upstream or pull manually"
                git stash pop || warning "Could not restore stashed changes"
            else
                REMOTE=$(echo "$UPSTREAM" | cut -d'/' -f1)
                REMOTE_BRANCH=$(echo "$UPSTREAM" | cut -d'/' -f2-)

                if git pull "$REMOTE" "$REMOTE_BRANCH"; then
                    success "Dotfiles updated from GitHub"
                    info "Applying stashed changes..."
                    if git stash pop; then
                        success "Local changes reapplied"
                    else
                        warning "Conflict while applying stashed changes"
                        info "Your changes are saved in git stash"
                        info "Run 'git stash list' to see them"
                    fi
                else
                    error "Failed to update from GitHub"
                    git stash pop || warning "Could not restore stashed changes"
                fi
            fi
        else
            # No local changes, safe to pull
            # Get current branch and upstream for explicit pull
            CURRENT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null)
            UPSTREAM=$(git for-each-ref --format='%(upstream:short)' "refs/heads/$CURRENT_BRANCH" 2>/dev/null)

            if [[ -z "$UPSTREAM" ]]; then
                warning "Current branch '$CURRENT_BRANCH' is not tracking any remote branch"
                info "Skipping update - please set upstream or pull manually"
            else
                REMOTE=$(echo "$UPSTREAM" | cut -d'/' -f1)
                REMOTE_BRANCH=$(echo "$UPSTREAM" | cut -d'/' -f2-)

                if git pull "$REMOTE" "$REMOTE_BRANCH"; then
                    success "Dotfiles updated from GitHub"
                else
                    warning "Failed to update from GitHub (check your connection)"
                fi
            fi
        fi
    fi
else
    warning "Dotfiles not found in iCloud"
    info "Cloning from GitHub..."

    # Ensure parent directory exists
    PARENT_DIR="$(dirname "$DOTFILES_DIR")"
    if [[ ! -d "$PARENT_DIR" ]]; then
        step "Creating directory: $PARENT_DIR"
        mkdir -p "$PARENT_DIR"
    fi

    # Check SSH connectivity to GitHub before attempting SSH clone
    USE_SSH=false
    if verify_ssh_agent; then
        # Test actual SSH connectivity to GitHub
        step "Testing SSH access to GitHub..."
        if ssh -T git@github.com -o BatchMode=yes -o ConnectTimeout=5 2>&1 | grep -q "successfully authenticated"; then
            success "SSH authentication to GitHub successful"
            info "Will use SSH for cloning"
            USE_SSH=true
        else
            warning "SSH agent present, but GitHub SSH authentication failed"
            info "Will use HTTPS instead"
            info "You can switch to SSH later with:"
            info "  cd $DOTFILES_DIR"
            info "  git remote set-url origin git@github.com:romanborodavkin/dotfiles.git"
        fi
    else
        warning "SSH agent not available, will use HTTPS"
        info "You can switch to SSH later with:"
        info "  cd $DOTFILES_DIR"
        info "  git remote set-url origin git@github.com:romanborodavkin/dotfiles.git"
    fi

    # Clone dotfiles repository
    if [[ "$USE_SSH" == "true" ]]; then
        if git clone git@github.com:romanborodavkin/dotfiles.git "$DOTFILES_DIR"; then
            success "Dotfiles cloned via SSH"
        else
            error "Failed to clone via SSH despite agent being available"
            warning "Falling back to HTTPS..."
            if git clone https://github.com/romanborodavkin/dotfiles.git "$DOTFILES_DIR"; then
                success "Dotfiles cloned via HTTPS"
            else
                error "Failed to clone dotfiles"
                exit 1
            fi
        fi
    else
        if git clone https://github.com/romanborodavkin/dotfiles.git "$DOTFILES_DIR"; then
            success "Dotfiles cloned via HTTPS"
        else
            error "Failed to clone dotfiles"
            exit 1
        fi
    fi
fi

# Check if Oh My Zsh is installed
title "Oh My Zsh check"

if [[ -d "$HOME/.oh-my-zsh" ]]; then
    success "Oh My Zsh already installed"
else
    warning "Oh My Zsh not installed"
    info "Installing Oh My Zsh..."

    # Install Oh My Zsh (prevent it from changing shell)
    # NOTE: This downloads and executes a remote script - standard Oh My Zsh installation method
    # Source: https://ohmyz.sh/#install (official installation instructions)
    RUNZSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

    if [[ -d "$HOME/.oh-my-zsh" ]]; then
        success "Oh My Zsh installed"
    else
        error "Failed to install Oh My Zsh"
        exit 1
    fi
fi

# Install Powerlevel10k theme
title "Powerlevel10k check"

if app_in_brew "powerlevel10k"; then
    success "Powerlevel10k already installed"
else
    step "Installing Powerlevel10k..."
    if brew install powerlevel10k; then
        success "Powerlevel10k installed"
    else
        error "Failed to install Powerlevel10k"
        error "ZSH theme may not work correctly"
        exit 1
    fi
fi

# Install ZSH plugins
title "Installing ZSH plugins"

plugins=(
    "zsh-autosuggestions"
    "zsh-syntax-highlighting"
    "zsh-history-substring-search"
    "fzf"
)

FAILED_PLUGINS=()

for plugin in "${plugins[@]}"; do
    if app_in_brew "$plugin"; then
        info "✓ $plugin already installed"
    else
        step "Installing $plugin..."
        if brew install "$plugin"; then
            success "$plugin installed"
        else
            error "Failed to install $plugin"
            FAILED_PLUGINS+=("$plugin")
        fi
    fi
done

# Report failed plugin installations
if [[ ${#FAILED_PLUGINS[@]} -gt 0 ]]; then
    echo ""
    warning "Some ZSH plugins failed to install:"
    for failed in "${FAILED_PLUGINS[@]}"; do
        info "  • $failed"
    done
    warning "Shell may have reduced functionality"
    echo ""
fi

# Run dotfiles installation script
title "Installing dotfiles"

# Change to dotfiles directory with error handling
if ! cd "$DOTFILES_DIR" 2>/dev/null; then
    error "Cannot access dotfiles directory: $DOTFILES_DIR"
    exit 1
fi

# Verify install.sh exists before attempting to execute
if [[ ! -f "install.sh" ]]; then
    error "install.sh not found in $DOTFILES_DIR"
    error "Repository may be incomplete or corrupted"
    info "Try removing $DOTFILES_DIR and running script again"
    exit 1
fi

# Make install script executable
if ! chmod +x install.sh 2>/dev/null; then
    error "Cannot make install.sh executable (permission denied)"
    exit 1
fi

# Fix the hardcoded path in .zshrc before running
if [[ -f "$DOTFILES_DIR/zsh/.zshrc" ]]; then
    step "Updating paths in .zshrc..."

    # Escape special characters in path for sed
    ESCAPED_PATH=$(printf '%s\n' "$DOTFILES_DIR" | sed 's:[\\/&]:\\&:g')

    # Use safe sed with proper error handling
    if sed -i.bak "s|DOTFILES_DIR=\"[^\"]*\"|DOTFILES_DIR=\"$ESCAPED_PATH\"|g" "$DOTFILES_DIR/zsh/.zshrc" 2>/dev/null; then
        # Remove backup only if sed succeeded
        rm -f "$DOTFILES_DIR/zsh/.zshrc.bak"
        success "Updated paths in .zshrc"
    else
        error "Failed to update .zshrc (file may be read-only)"
        # Restore from backup if it exists
        if [[ -f "$DOTFILES_DIR/zsh/.zshrc.bak" ]]; then
            mv "$DOTFILES_DIR/zsh/.zshrc.bak" "$DOTFILES_DIR/zsh/.zshrc"
            warning "Restored original .zshrc"
        fi
        exit 1
    fi
fi

# Verify install.sh is readable and executable
if [[ ! -r "install.sh" ]]; then
    error "install.sh is not readable (permission denied)"
    exit 1
fi

if [[ ! -x "install.sh" ]]; then
    error "install.sh is not executable after chmod"
    exit 1
fi

# Run installation
info "Running install.sh..."
if ./install.sh; then
    success "install.sh completed successfully"
else
    INSTALL_EXIT=$?
    error "install.sh failed with exit code: $INSTALL_EXIT"
    info "Check the output above for specific errors"
    exit 1
fi

# Comprehensive installation verification
step "Verifying dotfiles installation..."

VERIFICATION_FAILED=false

# Check core files
if [[ ! -f "$HOME/.zshrc" ]]; then
    error "$HOME/.zshrc not created"
    VERIFICATION_FAILED=true
fi

if [[ ! -f "$HOME/.zshenv" ]]; then
    error "$HOME/.zshenv not created"
    VERIFICATION_FAILED=true
fi

# Check if files are readable
if [[ -f "$HOME/.zshrc" ]] && [[ ! -r "$HOME/.zshrc" ]]; then
    error "$HOME/.zshrc exists but is not readable"
    VERIFICATION_FAILED=true
fi

# Check if .zshrc sources dotfiles correctly
if [[ -f "$HOME/.zshrc" ]] && ! grep -q "DOTFILES_DIR" "$HOME/.zshrc" 2>/dev/null; then
    warning "$HOME/.zshrc may not be properly configured (DOTFILES_DIR not found)"
fi

if [[ "$VERIFICATION_FAILED" == "true" ]]; then
    error "Dotfiles installation verification failed"
    info "Expected files:"
    info "  • $HOME/.zshrc (shell configuration)"
    info "  • $HOME/.zshenv (environment variables)"
    exit 1
else
    success "Dotfiles installed successfully!"
    info "Verified: $HOME/.zshrc and $HOME/.zshenv"
fi

# Set ZSH as default shell if needed
if [[ "$SHELL" != */zsh ]]; then
    title "Change default shell to ZSH"

    if confirm "Set ZSH as default shell?" "y"; then
        if command_exists zsh; then
            ZSH_PATH="$(command -v zsh)"

            # Check if zsh is in /etc/shells
            if ! grep -q "^${ZSH_PATH}$" /etc/shells 2>/dev/null; then
                warning "ZSH path not found in /etc/shells: $ZSH_PATH"
                info "Adding ZSH to /etc/shells (requires sudo)..."

                if echo "$ZSH_PATH" | sudo tee -a /etc/shells >/dev/null; then
                    success "Added $ZSH_PATH to /etc/shells"
                else
                    error "Failed to add ZSH to /etc/shells"
                    info "Run manually: sudo sh -c 'echo $ZSH_PATH >> /etc/shells'"
                    exit 1
                fi
            fi

            # Change shell
            if chsh -s "$ZSH_PATH"; then
                success "ZSH set as default shell"
                info "Changes take effect after restarting the terminal"
            else
                error "Failed to change default shell"
                info "Try manually: chsh -s $ZSH_PATH"
                exit 1
            fi
        else
            error "ZSH not found"
            info "Install ZSH first: brew install zsh"
            exit 1
        fi
    fi
else
    success "ZSH already is the default shell"
fi

echo ""
success "Dotfiles configured!"
info "Start a new terminal session or run: exec zsh"
echo ""
