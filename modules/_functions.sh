#!/bin/bash
# functions.sh - Helper functions for all scripts

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Output functions
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }
warning() { echo -e "${YELLOW}[⚠]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; }
step() { echo -e "${CYAN}[→]${NC} $1"; }
title() {
    echo ""
    echo -e "${BOLD}$1${NC}"
    printf '%.0s─' {1..60}
    echo
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Ask for confirmation
confirm() {
    local prompt="${1:-Continue?}"
    local default="${2:-n}"

    if [[ "$default" == "y" ]]; then
        prompt="$prompt [Y/n]: "
    else
        prompt="$prompt [y/N]: "
    fi

    read -p "$prompt" -n 1 -r
    echo
    if [[ "$default" == "y" ]]; then
        [[ $REPLY =~ ^[Nn]$ ]] && return 1 || return 0
    else
        [[ $REPLY =~ ^[Yy]$ ]] && return 0 || return 1
    fi
}

# Backup file if exists
backup_file() {
    local file="$1"
    if [[ -f "$file" ]] || [[ -L "$file" ]]; then
        local timestamp
        timestamp=$(date +%Y%m%d_%H%M%S)
        local backup="${file}.backup.${timestamp}"
        mv "$file" "$backup"
        warning "Backed up: $file → $backup"
    fi
}

# Create symlink with backup
create_symlink() {
    local source="$1"
    local target="$2"

    if [[ ! -e "$source" ]]; then
        error "Source does not exist: $source"
        return 1
    fi

    backup_file "$target"
    [[ -e "$target" ]] && rm -f "$target"

    ln -sf "$source" "$target"
    if [[ -L "$target" ]]; then
        success "Symlink created: $target → $source"
        return 0
    else
        error "Failed to create symlink: $target"
        return 1
    fi
}

# Load configuration
load_config() {
    local config_file="$1"
    if [[ -f "$config_file" ]]; then
        # shellcheck source=/dev/null
        source "$config_file"
        return 0
    else
        error "Configuration not found: $config_file"
        return 1
    fi
}

# Check if running on macOS
check_macos() {
    if [[ "$OSTYPE" != "darwin"* ]]; then
        error "This script is intended only for macOS"
        exit 1
    fi
}

# Get macOS version
get_macos_version() {
    sw_vers -productVersion
}

# Check if Apple Silicon
is_apple_silicon() {
    [[ $(uname -m) == "arm64" ]]
}

# Progress bar
progress_bar() {
    local duration=$1
    local increment=$((duration / 50))
    local elapsed=0

    echo -n "["
    while [[ $elapsed -lt $duration ]]; do
        echo -n "#"
        sleep $increment
        elapsed=$((elapsed + increment))
    done
    echo "]"
}

# Spinner
spinner() {
    local pid=$!
    local delay=0.1
    local spin_chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'

    while ps -p $pid > /dev/null; do
        local temp=${spin_chars#?}
        printf " [%c]  " "$spin_chars"
        spin_chars=$temp${spin_chars%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# Check if app is installed via brew
app_in_brew() {
    local app="$1"
    brew list --cask "$app" &>/dev/null || brew list --formula "$app" &>/dev/null
}

# Check if app is installed via mas
app_in_mas() {
    local app_id="$1"
    mas list | grep -q "^$app_id"
}

# Detect iCloud Drive directory
detect_icloud_dir() {
    # Try standard path first
    local standard="$HOME/Library/Mobile Documents/com~apple~CloudDocs"
    if [[ -d "$standard" ]]; then
        echo "$standard"
        return 0
    fi

    # Try to find via mdfind
    local found
    found=$(mdfind -onlyin "$HOME/Library" 'kMDItemDisplayName == "iCloud Drive"' 2>/dev/null | head -1)
    if [[ -n "$found" && -d "$found" ]]; then
        echo "$found"
        return 0
    fi

    return 1
}

# Check if iCloud folder is synced (not just placeholders)
check_icloud_sync() {
    local dir="$1"

    # Check if directory is writable
    local test_file="$dir/.icloud_test_$$"
    if ! touch "$test_file" 2>/dev/null; then
        error "iCloud folder exists but not writable (still syncing?)"
        return 1
    fi
    rm -f "$test_file"

    # Check for .icloud placeholder files
    if find "$dir" -name "*.icloud" 2>/dev/null | grep -q .; then
        error "iCloud files still downloading (found .icloud placeholders)"
        info "Wait for iCloud sync to complete and try again"
        return 1
    fi

    return 0
}

# Check internet connection with multiple endpoints
check_internet() {
    local test_urls=(
        "https://www.apple.com"
        "https://github.com"
        "https://raw.githubusercontent.com"
    )

    for url in "${test_urls[@]}"; do
        if curl -s --connect-timeout 5 -I "$url" > /dev/null 2>&1; then
            success "Internet connection verified ($url)"
            return 0
        fi
    done

    error "Cannot reach any test URLs"
    error "Check: WiFi, VPN, Firewall, Captive Portal"
    return 1
}

# Load and validate system configuration
load_system_config() {
    local script_dir="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
    local config="$script_dir/config/system.conf"

    if [[ ! -f "$config" ]]; then
        error "system.conf not found. Did preflight run?"
        error "Try: $script_dir/scripts/01-preflight.sh"
        exit 1
    fi

    # shellcheck source=/dev/null
    source "$config"

    # Validate required variables
    [[ -z "$MACOS_VERSION" ]] && { error "MACOS_VERSION not set in config"; exit 1; }
    [[ -z "$ARCH" ]] && { error "ARCH not set in config"; exit 1; }
    [[ -z "$HOMEBREW_PREFIX" ]] && { error "HOMEBREW_PREFIX not set in config"; exit 1; }
    [[ -z "$ICLOUD_DIR" ]] && { error "ICLOUD_DIR not set in config"; exit 1; }

    return 0
}

# Verify command is installed and accessible
verify_command() {
    local cmd="$1"
    local name="${2:-$cmd}"

    if command_exists "$cmd"; then
        success "$name installed and accessible"
        return 0
    else
        error "$name not found in PATH"
        return 1
    fi
}

# Verify app is installed via brew
verify_app() {
    local app="$1"

    if app_in_brew "$app"; then
        success "$app installed"
        return 0
    else
        error "$app not found"
        return 1
    fi
}

# Verify SSH agent is running and has keys
verify_ssh_agent() {
    if ssh-add -l &>/dev/null; then
        success "SSH agent ready with keys"
        return 0
    elif [[ $? -eq 1 ]]; then
        warning "SSH agent running but no keys loaded"
        return 1
    else
        error "SSH agent not accessible"
        return 1
    fi
}

# Verification system
VERIFY_TOTAL=0
VERIFY_PASSED=0
VERIFY_FAILED=0
VERIFY_WARNINGS=0
declare -a VERIFY_ERRORS=()
declare -a VERIFY_WARNS=()

verify_pass() {
    VERIFY_TOTAL=$((VERIFY_TOTAL + 1))
    VERIFY_PASSED=$((VERIFY_PASSED + 1))
    success "$1"
}

verify_fail() {
    VERIFY_TOTAL=$((VERIFY_TOTAL + 1))
    VERIFY_FAILED=$((VERIFY_FAILED + 1))
    error "$1"
    VERIFY_ERRORS+=("$1")
}

verify_warn() {
    VERIFY_TOTAL=$((VERIFY_TOTAL + 1))
    VERIFY_WARNINGS=$((VERIFY_WARNINGS + 1))
    warning "$1"
    VERIFY_WARNS+=("$1")
}

verify_directory() {
    local dir="$1"
    local name="${2:-$dir}"
    if [[ -d "$dir" ]]; then
        verify_pass "$name exists"
        return 0
    else
        verify_fail "$name not found: $dir"
        return 1
    fi
}

verify_file() {
    local file="$1"
    local name="${2:-$file}"
    if [[ -f "$file" ]]; then
        verify_pass "$name exists"
        return 0
    else
        verify_fail "$name not found: $file"
        return 1
    fi
}

verify_symlink() {
    local target="$1"
    local source="$2"
    local name="${3:-$target}"

    if [[ -L "$target" ]]; then
        local actual_source
        actual_source=$(readlink "$target")
        if [[ "$actual_source" == "$source" ]]; then
            verify_pass "$name: symlink correct ($target → $source)"
            return 0
        else
            verify_warn "$name: symlink exists but points to: $actual_source (expected: $source)"
            return 1
        fi
    else
        verify_fail "$name: not a symlink"
        return 1
    fi
}

verify_process() {
    local process="$1"
    local name="${2:-$process}"

    if pgrep -x "$process" >/dev/null; then
        verify_pass "$name is running"
        return 0
    else
        verify_warn "$name is not running"
        return 1
    fi
}

# Reset verification counters
reset_verify_counters() {
    VERIFY_TOTAL=0
    VERIFY_PASSED=0
    VERIFY_FAILED=0
    VERIFY_WARNINGS=0
    VERIFY_ERRORS=()
    VERIFY_WARNS=()
}

# Show verification summary
show_verify_summary() {
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo "                      Verification Summary                      "
    echo "════════════════════════════════════════════════════════════════"
    echo ""

    info "📊 Results:"
    echo "   • Total checks: $VERIFY_TOTAL"
    echo "   • Passed: $VERIFY_PASSED ✅"
    echo "   • Warnings: $VERIFY_WARNINGS ⚠️"
    echo "   • Failed: $VERIFY_FAILED ❌"
    echo ""

    if [[ $VERIFY_TOTAL -gt 0 ]]; then
        local success_pct=$((VERIFY_PASSED * 100 / VERIFY_TOTAL))
        echo "Success rate: ${success_pct}%"
        echo ""
    fi

    if [[ $VERIFY_FAILED -gt 0 ]]; then
        echo "════════════════════════════════════════════════════════════════"
        error "❌ Critical Issues Found:"
        echo "════════════════════════════════════════════════════════════════"
        for err in "${VERIFY_ERRORS[@]}"; do
            echo "  • $err"
        done
        echo ""
    fi

    if [[ $VERIFY_WARNINGS -gt 0 ]]; then
        echo "════════════════════════════════════════════════════════════════"
        warning "⚠️  Warnings (non-critical):"
        echo "════════════════════════════════════════════════════════════════"
        for warn in "${VERIFY_WARNS[@]}"; do
            echo "  • $warn"
        done
        echo ""
    fi

    echo "════════════════════════════════════════════════════════════════"
    if [[ $VERIFY_FAILED -eq 0 ]] && [[ $VERIFY_WARNINGS -eq 0 ]]; then
        success "🎉 Perfect! Everything is properly configured!"
    elif [[ $VERIFY_FAILED -eq 0 ]]; then
        success "✅ Setup completed with minor warnings"
        info "System is functional but some optional components need attention"
    else
        error "⚠️  Setup incomplete - please fix critical issues above"
    fi
    echo "════════════════════════════════════════════════════════════════"
    echo ""
}

# Cleanup package manager caches
cleanup_package_caches() {
    title "Cleaning package manager caches"

    local cleaned=0
    if command_exists brew; then
        step "Cleaning Homebrew cache..."
        brew cleanup --prune=all 2>/dev/null && cleaned=$((cleaned + 1))
        brew autoremove 2>/dev/null || true
        success "Homebrew cache cleared"
    fi

    if command_exists npm; then
        step "Cleaning npm cache..."
        npm cache clean --force 2>/dev/null && cleaned=$((cleaned + 1))
        success "npm cache cleared"
    fi

    if command_exists pip3; then
        step "Cleaning pip cache..."
        pip3 cache purge 2>/dev/null && cleaned=$((cleaned + 1))
        success "pip cache cleared"
    fi

    info "Cleaned $cleaned package manager cache(s)"
}

# Cleanup temporary files from setup process
cleanup_temp_files() {
    title "Cleaning temporary setup files"

    # Sudo keepalive files from preflight
    shopt -s nullglob
    local sudo_files=(/tmp/macos-setup-sudo-*)
    shopt -u nullglob

    if [[ ${#sudo_files[@]} -gt 0 ]]; then
        rm -f "${sudo_files[@]}" 2>/dev/null || true
        success "Removed ${#sudo_files[@]} sudo keepalive file(s)"
    fi

    # Old backup files (older than 30 days)
    local backup_count=0
    backup_count=$(find "$HOME" -maxdepth 1 -name "*.backup.*" -type f -mtime +30 2>/dev/null | wc -l | tr -d ' ')
    if [[ $backup_count -gt 0 ]]; then
        find "$HOME" -maxdepth 1 -name "*.backup.*" -type f -mtime +30 -delete 2>/dev/null || true
        success "Removed $backup_count old backup file(s) (>30 days)"
    fi
}

# Cleanup old reports and logs
cleanup_old_reports() {
    title "Cleaning old reports"

    # Remove old setup reports from Desktop (older than 7 days)
    local report_count=0
    report_count=$(find "$HOME/Desktop" -name "macos-setup-report-*.txt" -type f -mtime +7 2>/dev/null | wc -l | tr -d ' ')
    if [[ $report_count -gt 0 ]]; then
        find "$HOME/Desktop" -name "macos-setup-report-*.txt" -type f -mtime +7 -delete 2>/dev/null || true
        success "Removed $report_count old report(s) from Desktop"
    fi

    # Remove old verify logs if they exist
    if [[ -d "$HOME/.macos-setup/logs" ]]; then
        local log_count=0
        log_count=$(find "$HOME/.macos-setup/logs" -name "verify-*.log" -type f -mtime +7 2>/dev/null | wc -l | tr -d ' ')
        if [[ $log_count -gt 0 ]]; then
            find "$HOME/.macos-setup/logs" -name "verify-*.log" -type f -mtime +7 -delete 2>/dev/null || true
            success "Removed $log_count old verify log(s)"
        fi
    fi
}

# Generate setup report with verify integration
generate_setup_report() {
    local report_file="$1"
    local verify_status="${2:-unknown}"

    {
        echo "════════════════════════════════════════════════════════════════"
        echo "                macOS Setup Report"
        echo "                $(date '+%Y-%m-%d %H:%M:%S')"
        echo "════════════════════════════════════════════════════════════════"
        echo ""
        echo "VERIFICATION STATUS: $verify_status"
        echo ""
        echo "SYSTEM INFORMATION:"
        echo "-------------------"
        echo "macOS Version: $(sw_vers -productVersion)"
        echo "Architecture: $(uname -m)"
        echo "Hostname: $(hostname)"
        echo "User: $USER"
        echo ""
        echo "INSTALLED SOFTWARE:"
        echo "------------------"
        echo "Homebrew formulas: $(brew list --formula 2>/dev/null | wc -l || echo 'N/A')"
        echo "Homebrew casks: $(brew list --cask 2>/dev/null | wc -l || echo 'N/A')"
        echo "Mac App Store apps: $(mas list 2>/dev/null | wc -l || echo 'N/A')"
        echo ""
        echo "SHELL CONFIGURATION:"
        echo "-------------------"
        echo "Current shell: $SHELL"
        echo "ZSH version: $(zsh --version 2>/dev/null || echo 'N/A')"
        echo "Oh My Zsh: $([ -d "$HOME/.oh-my-zsh" ] && echo 'Installed' || echo 'Not installed')"
        echo ""
        echo "DEVELOPMENT TOOLS:"
        echo "-----------------"
        echo "Git: $(git --version 2>/dev/null || echo 'Not installed')"
        echo "Python: $(python3 --version 2>/dev/null || echo 'Not installed')"
        echo "Node.js: $(node --version 2>/dev/null || echo 'Not installed')"
        echo "Docker: $(docker --version 2>/dev/null || echo 'Not installed')"
        echo ""
        echo "DOTFILES:"
        echo "--------"
        echo "Location: ${DOTFILES_DIR:-Not set}"
        echo ".zshrc: $([ -f "$HOME/.zshrc" ] && echo 'Present' || echo 'Missing')"
        echo ".zshenv: $([ -f "$HOME/.zshenv" ] && echo 'Present' || echo 'Missing')"
        echo ""
        echo "1PASSWORD SSH:"
        echo "-------------"
        echo "SSH config: $([ -f "$HOME/.ssh/config" ] && echo 'Present' || echo 'Missing')"
        echo "SSH agent: $(ssh-add -l &>/dev/null && echo 'Working' || echo 'Not configured')"
        echo ""
        echo "MACKUP:"
        echo "------"
        echo "Config: $([ -f "$HOME/.mackup.cfg" ] && echo 'Present' || echo 'Missing')"
        echo "Backup location: $HOME/Library/Mobile Documents/com~apple~CloudDocs/2. Backup/mackup"
        echo ""
        echo "════════════════════════════════════════════════════════════════"
    } | tee "$report_file"
}

# Export all functions
export -f info success warning error step title
export -f command_exists confirm backup_file create_symlink
export -f load_config check_macos get_macos_version is_apple_silicon
export -f progress_bar spinner app_in_brew app_in_mas
export -f detect_icloud_dir check_icloud_sync check_internet
export -f load_system_config verify_command verify_app verify_ssh_agent
export -f verify_pass verify_fail verify_warn verify_directory verify_file
export -f verify_symlink verify_process reset_verify_counters show_verify_summary
export -f cleanup_package_caches cleanup_temp_files cleanup_old_reports generate_setup_report
