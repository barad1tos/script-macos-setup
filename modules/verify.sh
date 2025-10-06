#!/bin/bash
# 98-verify.sh - Comprehensive verification of entire macOS setup
set -euo pipefail

# Source helper functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/modules/_functions.sh"

# Load system configuration (optional for verification)
if [[ -f "$SCRIPT_DIR/config/system.conf" ]]; then
    # shellcheck source=/dev/null
    source "$SCRIPT_DIR/config/system.conf"
fi

# Categories to verify (default: all)
CATEGORIES=()
LOG_FILE=""
VERBOSE=false

# Parse CLI arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --category|-c)
                IFS=',' read -ra CATEGORIES <<< "$2"
                shift 2
                ;;
            --log|-l)
                LOG_FILE="$2"
                shift 2
                ;;
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --help|-h)
                show_usage
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    # Default: all categories
    if [[ ${#CATEGORIES[@]} -eq 0 ]]; then
        CATEGORIES=("core" "packages" "security" "dev" "prefs" "mackup" "state")
    fi
}

show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Comprehensive verification of macOS setup.

OPTIONS:
    -c, --category <list>   Comma-separated categories to verify
                            Available: core,packages,security,dev,prefs,mackup,state
                            Default: all
    -l, --log <file>        Save results to log file
    -v, --verbose           Show detailed output
    -h, --help             Show this help message

EXAMPLES:
    $(basename "$0")                              # Verify everything
    $(basename "$0") -c core,security             # Only core and security
    $(basename "$0") -c dev -l verify.log         # Dev environment, save log
    $(basename "$0") -c packages --verbose        # Packages with details

CATEGORIES:
    core      - Core System (macOS, disk, Xcode)
    packages  - Package Management (Homebrew, MAS)
    security  - Security & Authentication (1Password, SSH)
    dev       - Development Environment (dotfiles, shell)
    prefs     - System Preferences
    mackup    - App Settings Sync
    state     - System State (directories, processes)
EOF
}

# ════════════════════════════════════════════════════════════════
# Category 1: Core System
# ════════════════════════════════════════════════════════════════
verify_core_system() {
    title "[1/7] Core System"

    # macOS version
    local macos_version
    macos_version=$(sw_vers -productVersion)
    if [[ -n "$macos_version" ]]; then
        verify_pass "macOS version: $macos_version"
    else
        verify_fail "Cannot detect macOS version"
    fi

    # Disk space check
    local available_gb
    available_gb=$(df -g / | awk 'NR==2 {print $4}')
    if [[ $available_gb -gt 50 ]]; then
        verify_pass "Disk space: ${available_gb}GB available"
    elif [[ $available_gb -gt 20 ]]; then
        verify_warn "Disk space: ${available_gb}GB available (consider freeing space)"
    else
        verify_fail "Disk space: ${available_gb}GB available (critically low!)"
    fi

    # Xcode Command Line Tools
    if verify_command xcode-select "Xcode Command Line Tools"; then
        local xcode_path
        xcode_path=$(xcode-select -p 2>/dev/null)
        if [[ -n "$xcode_path" ]] && [[ -d "$xcode_path" ]]; then
            [[ $VERBOSE == true ]] && info "   • Path: $xcode_path"
            # Verify critical tools exist
            if [[ -x "$xcode_path/usr/bin/git" ]] || [[ -x "$xcode_path/usr/bin/clang" ]]; then
                verify_pass "Xcode Command Line Tools properly installed"
            else
                verify_fail "Xcode Command Line Tools directory exists but tools missing"
            fi
        else
            verify_fail "Xcode Command Line Tools path invalid or missing"
        fi
    fi

    echo ""
}

# ════════════════════════════════════════════════════════════════
# Category 2: Package Management
# ════════════════════════════════════════════════════════════════
verify_package_management() {
    title "[2/7] Package Management"

    # Homebrew
    if verify_command brew "Homebrew"; then
        local brew_version
        brew_version=$(brew --version | head -1)
        [[ $VERBOSE == true ]] && info "   • $brew_version"

        # Brewfile packages check
        local brewfile="$SCRIPT_DIR/config/Brewfile"
        if [[ -f "$brewfile" ]]; then
            step "Checking Brewfile packages..."
            if brew bundle check --file="$brewfile" >/dev/null 2>&1; then
                verify_pass "All Brewfile packages installed"
            else
                local missing_count
                missing_count=$(brew bundle check --file="$brewfile" 2>&1 | grep -c "not installed" || echo "0")
                if [[ $missing_count -gt 0 ]]; then
                    verify_warn "Brewfile: $missing_count package(s) missing"
                else
                    verify_warn "Some Brewfile packages may be missing"
                fi
            fi
        else
            verify_warn "Brewfile not found at: $brewfile"
        fi

        # Package counts
        if [[ $VERBOSE == true ]]; then
            local formula_count cask_count
            formula_count=$(brew list --formula 2>/dev/null | wc -l | tr -d ' ')
            cask_count=$(brew list --cask 2>/dev/null | wc -l | tr -d ' ')
            info "   • Formulas installed: $formula_count"
            info "   • Casks installed: $cask_count"
        fi
    fi

    # Mac App Store
    if command_exists mas; then
        if mas account &>/dev/null; then
            local mas_account
            mas_account=$(mas account)
            verify_pass "Mac App Store: signed in as $mas_account"
            if [[ $VERBOSE == true ]]; then
                local mas_count
                mas_count=$(mas list 2>/dev/null | wc -l | tr -d ' ')
                info "   • MAS apps installed: $mas_count"
            fi
        else
            verify_warn "Mac App Store: not signed in"
        fi
    else
        verify_warn "mas (Mac App Store CLI) not installed"
    fi

    echo ""
}

# ════════════════════════════════════════════════════════════════
# Category 3: Security & Authentication
# ════════════════════════════════════════════════════════════════
verify_security() {
    title "[3/7] Security & Authentication"

    # 1Password
    verify_process "1Password" "1Password app"

    # SSH agent
    if verify_ssh_agent 2>/dev/null; then
        local key_output key_count
        key_output=$(ssh-add -l 2>/dev/null || echo "")
        if echo "$key_output" | grep -q "no identities"; then
            verify_warn "SSH agent running but no keys loaded"
        else
            key_count=$(echo "$key_output" | wc -l | tr -d ' ')
            verify_pass "SSH agent: $key_count key(s) loaded"
        fi
    else
        verify_warn "SSH agent not available"
    fi

    # op CLI
    if command_exists op; then
        if op account list &>/dev/null; then
            local account_count
            account_count=$(op account list 2>/dev/null | wc -l | tr -d ' ')
            verify_pass "op CLI: $account_count account(s) configured"
        else
            verify_warn "op CLI installed but not authenticated"
        fi
    else
        verify_warn "op CLI not installed"
    fi

    # SSH config
    if [[ -f "$HOME/.ssh/config" ]]; then
        if grep -q "IdentityAgent" "$HOME/.ssh/config" 2>/dev/null; then
            verify_pass "SSH config: 1Password agent configured"
        else
            verify_warn "SSH config exists but 1Password agent not configured"
        fi
    else
        verify_warn "SSH config file not found"
    fi

    echo ""
}

# ════════════════════════════════════════════════════════════════
# Category 4: Development Environment
# ════════════════════════════════════════════════════════════════
verify_development() {
    title "[4/7] Development Environment"

    # Dotfiles directory
    local dotfiles_dir="${DOTFILES_DIR:-$HOME/Library/Mobile Documents/com~apple~CloudDocs/3. Git/Own/dotfiles}"
    dotfiles_dir="${dotfiles_dir/#\~/$HOME}"  # Expand tilde if present
    verify_directory "$dotfiles_dir/.git" "Dotfiles repository"

    # Shell configuration files
    verify_file "$HOME/.zshrc" ".zshrc"
    if [[ -f "$HOME/.zshrc" ]] && grep -q "DOTFILES_DIR" "$HOME/.zshrc" 2>/dev/null; then
        verify_pass ".zshrc properly configured with DOTFILES_DIR"
    elif [[ -f "$HOME/.zshrc" ]]; then
        verify_warn ".zshrc may not be properly configured"
    fi

    verify_file "$HOME/.zshenv" ".zshenv"

    # Oh My Zsh
    verify_directory "$HOME/.oh-my-zsh" "Oh My Zsh"

    # Powerlevel10k
    if app_in_brew powerlevel10k; then
        verify_pass "Powerlevel10k theme installed"
    else
        verify_warn "Powerlevel10k not installed via Homebrew"
    fi

    # Default shell
    if [[ "$SHELL" == *"zsh"* ]]; then
        local zsh_version
        zsh_version=$(zsh --version 2>/dev/null || echo "unknown")
        verify_pass "ZSH is default shell ($zsh_version)"
    else
        verify_warn "ZSH is not the default shell (current: $SHELL)"
    fi

    # ZSH plugins
    local plugins_missing=0
    local plugins=("zsh-autosuggestions" "zsh-syntax-highlighting" "zsh-history-substring-search" "fzf")
    for plugin in "${plugins[@]}"; do
        if app_in_brew "$plugin"; then
            [[ $VERBOSE == true ]] && info "   ✓ $plugin installed"
        else
            [[ $VERBOSE == true ]] && info "   ✗ $plugin missing"
            plugins_missing=$((plugins_missing + 1))
        fi
    done

    if [[ $plugins_missing -eq 0 ]]; then
        verify_pass "All ZSH plugins installed"
    else
        verify_warn "$plugins_missing ZSH plugin(s) missing"
    fi

    echo ""
}

# ════════════════════════════════════════════════════════════════
# Category 5: System Preferences
# ════════════════════════════════════════════════════════════════
verify_system_preferences() {
    title "[5/7] System Preferences"

    # Computer name
    local computer_name
    computer_name=$(scutil --get ComputerName 2>/dev/null || echo "")
    if [[ -n "$computer_name" ]]; then
        verify_pass "Computer name: $computer_name"
    else
        verify_warn "Computer name not set"
    fi

    # Sample defaults check (Finder shows hidden files)
    if [[ $VERBOSE == true ]]; then
        local show_hidden
        show_hidden=$(defaults read com.apple.finder AppleShowAllFiles 2>/dev/null || echo "false")
        if [[ "$show_hidden" == "true" ]] || [[ "$show_hidden" == "1" ]]; then
            info "   • Finder: shows hidden files ✓"
        else
            info "   • Finder: hidden files not shown"
        fi
    fi

    verify_pass "System preferences script completed (partial validation)"

    echo ""
}

# ════════════════════════════════════════════════════════════════
# Category 6: App Settings Sync (Mackup)
# ════════════════════════════════════════════════════════════════
verify_mackup() {
    title "[6/7] App Settings Sync"

    # Mackup config
    verify_file "$HOME/.mackup.cfg" "Mackup configuration"

    # Check iCloud directory
    local mackup_dir="$HOME/Library/Mobile Documents/com~apple~CloudDocs/2. Backup/mackup"
    verify_directory "$mackup_dir" "Mackup iCloud directory"

    # Mackup installed
    verify_command mackup "Mackup"

    # Custom configs
    if [[ $VERBOSE == true ]]; then
        local custom_configs=("reeder.cfg" "warp.cfg" "zed.cfg")
        for config in "${custom_configs[@]}"; do
            if [[ -f "$HOME/.mackup/$config" ]]; then
                info "   ✓ Custom config: $config"
            else
                info "   ✗ Missing config: $config"
            fi
        done
    fi

    echo ""
}

# ════════════════════════════════════════════════════════════════
# Category 7: System State
# ════════════════════════════════════════════════════════════════
verify_system_state() {
    title "[7/7] System State"

    # Workspace directories
    local workspace_dirs=("$HOME/Dev" "$HOME/Dev/work" "$HOME/Dev/personal" "$HOME/Dev/learning")
    local missing_dirs=0
    for dir in "${workspace_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            [[ $VERBOSE == true ]] && info "   ✓ $dir exists"
        else
            [[ $VERBOSE == true ]] && info "   ✗ $dir missing"
            missing_dirs=$((missing_dirs + 1))
        fi
    done

    if [[ $missing_dirs -eq 0 ]]; then
        verify_pass "All workspace directories created"
    else
        verify_warn "$missing_dirs workspace director(ies) missing"
    fi

    # Check for hanging sudo processes
    shopt -s nullglob
    local sudo_pids=(/tmp/macos-setup-sudo-*)
    shopt -u nullglob
    if [[ ${#sudo_pids[@]} -gt 0 ]]; then
        verify_warn "Found ${#sudo_pids[@]} hanging sudo process(es)"
    else
        verify_pass "No hanging processes found"
    fi

    echo ""
}

# ════════════════════════════════════════════════════════════════
# Save results to log file
# ════════════════════════════════════════════════════════════════
save_to_log() {
    if [[ -n "$LOG_FILE" ]]; then
        # Create logs directory if needed
        local log_dir
        log_dir=$(dirname "$LOG_FILE")
        mkdir -p "$log_dir"

        {
            echo "════════════════════════════════════════════════════════════════"
            echo "macOS Setup Verification - $(date '+%Y-%m-%d %H:%M:%S')"
            echo "════════════════════════════════════════════════════════════════"
            echo ""
            echo "Categories verified: ${CATEGORIES[*]}"
            echo ""
            echo "Results:"
            echo "  • Total checks: $VERIFY_TOTAL"
            echo "  • Passed: $VERIFY_PASSED ✅"
            echo "  • Warnings: $VERIFY_WARNINGS ⚠️"
            echo "  • Failed: $VERIFY_FAILED ❌"
            echo ""

            if [[ $VERIFY_TOTAL -gt 0 ]]; then
                local success_pct=$((VERIFY_PASSED * 100 / VERIFY_TOTAL))
                echo "Success rate: ${success_pct}%"
                echo ""
            fi

            if [[ $VERIFY_FAILED -gt 0 ]]; then
                echo "Critical Issues:"
                for err in "${VERIFY_ERRORS[@]}"; do
                    echo "  ❌ $err"
                done
                echo ""
            fi

            if [[ $VERIFY_WARNINGS -gt 0 ]]; then
                echo "Warnings:"
                for warn in "${VERIFY_WARNS[@]}"; do
                    echo "  ⚠️  $warn"
                done
                echo ""
            fi

            echo "════════════════════════════════════════════════════════════════"
        } > "$LOG_FILE"

        success "Results saved to: $LOG_FILE"
    fi
}

# ════════════════════════════════════════════════════════════════
# Main execution
# ════════════════════════════════════════════════════════════════
main() {
    parse_args "$@"

    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo "          macOS Setup - Final Verification Check               "
    echo "════════════════════════════════════════════════════════════════"
    echo ""

    info "Verifying categories: ${CATEGORIES[*]}"
    [[ $VERBOSE == true ]] && info "Verbose mode: enabled"
    [[ -n "$LOG_FILE" ]] && info "Log file: $LOG_FILE"
    echo ""

    # Reset counters
    reset_verify_counters

    # Run selected categories
    for category in "${CATEGORIES[@]}"; do
        case $category in
            core)
                verify_core_system
                ;;
            packages)
                verify_package_management
                ;;
            security)
                verify_security
                ;;
            dev)
                verify_development
                ;;
            prefs)
                verify_system_preferences
                ;;
            mackup)
                verify_mackup
                ;;
            state)
                verify_system_state
                ;;
            *)
                error "Unknown category: $category"
                ;;
        esac
    done

    # Show summary
    show_verify_summary

    # Save to log if requested
    save_to_log

    # Suggested fixes
    if [[ $VERIFY_FAILED -gt 0 ]]; then
        info "💡 Recommended Actions:"
        if [[ " ${VERIFY_ERRORS[*]} " =~ Homebrew ]]; then
            echo "  • Run: scripts/03-homebrew.sh"
        fi
        if [[ " ${VERIFY_ERRORS[*]} " =~ Xcode ]]; then
            echo "  • Run: scripts/02-xcode.sh"
        fi
        if [[ " ${VERIFY_ERRORS[*]} " =~ Dotfiles ]] || [[ " ${VERIFY_ERRORS[*]} " =~ \.zshrc ]]; then
            echo "  • Run: scripts/05-dotfiles.sh"
        fi
        if [[ " ${VERIFY_ERRORS[*]} " =~ Mackup ]]; then
            echo "  • Run: scripts/07-mackup.sh"
        fi
        echo ""
    fi

    # Exit with appropriate code
    if [[ $VERIFY_FAILED -gt 0 ]]; then
        exit 1
    else
        exit 0
    fi
}

main "$@"
