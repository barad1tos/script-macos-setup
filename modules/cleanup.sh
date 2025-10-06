#!/bin/bash
# 99-cleanup.sh - Final cleanup and finalization
set -euo pipefail

# Source helper functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/modules/_functions.sh"

# CLI options
CLEANUP_MODE="full"  # quick|full
NO_RESTART=false
NO_REPORT=false

# Parse CLI arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --quick)
                CLEANUP_MODE="quick"
                shift
                ;;
            --full)
                CLEANUP_MODE="full"
                shift
                ;;
            --no-restart)
                NO_RESTART=true
                shift
                ;;
            --no-report)
                NO_REPORT=true
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
}

show_usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Final cleanup and system finalization.

OPTIONS:
    --quick         Quick cleanup (caches only)
    --full          Full cleanup including temp files (default)
    --no-restart    Skip restart prompt
    --no-report     Skip report generation
    -h, --help      Show this help message

EXAMPLES:
    $(basename "$0")                    # Full cleanup with report
    $(basename "$0") --quick            # Only clean caches
    $(basename "$0") --no-restart       # Cleanup without restart prompt
    $(basename "$0") --quick --no-report # Fast cleanup, no report

CLEANUP OPERATIONS:
    Quick mode:
      • Package manager caches (brew, npm, pip)

    Full mode (includes quick + ):
      • Temporary setup files (sudo keepalive)
      • Old backup files (>30 days)
      • Old reports and logs (>7 days)
EOF
}

# Main execution
main() {
    parse_args "$@"

    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo "                   Cleanup & Finalization                       "
    echo "════════════════════════════════════════════════════════════════"
    echo ""

    info "Cleanup mode: $CLEANUP_MODE"
    [[ "$NO_REPORT" == true ]] && info "Report generation: disabled"
    [[ "$NO_RESTART" == true ]] && info "Restart prompt: disabled"
    echo ""

    # Always clean package caches
    cleanup_package_caches
    echo ""

    # Full mode: clean temp files and old reports
    if [[ "$CLEANUP_MODE" == "full" ]]; then
        cleanup_temp_files
        echo ""
        cleanup_old_reports
        echo ""
    fi

    # Create workspace directories
    title "Creating workspace directories"

    # Load system config if available
    # Basic validation: check ownership and permissions for local Mac setup tool
    # Full content validation would be overkill for user-controlled config in same repo
    if [[ -f "$SCRIPT_DIR/config/system.conf" ]]; then
        local config_owner
        config_owner=$(stat -f "%Su" "$SCRIPT_DIR/config/system.conf")
        if [[ "$config_owner" == "$USER" ]]; then
            # shellcheck source=/dev/null
            source "$SCRIPT_DIR/config/system.conf"
        else
            warning "Skipping system.conf: file not owned by current user ($config_owner ≠ $USER)"
        fi
    fi

    # Default workspace directories
    local workspace_dirs=(
        "$HOME/Dev"
        "$HOME/Dev/work"
        "$HOME/Dev/personal"
        "$HOME/Dev/learning"
    )

    for dir in "${workspace_dirs[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            info "Created: $dir"
        else
            info "Exists: $dir"
        fi
    done
    echo ""

    # Run verification and generate report
    if [[ "$NO_REPORT" != true ]]; then
        title "Running final verification"

        local verify_status="✅ PASSED"
        if ! "$SCRIPT_DIR/scripts/98-verify.sh" >/dev/null 2>&1; then
            verify_status="❌ FAILED (run ./scripts/98-verify.sh for details)"
            warning "Verification found issues"
        else
            success "Verification passed"
        fi

        echo ""
        title "Generating installation report"

        local report_file
        report_file="$HOME/Desktop/macos-setup-report-$(date +%Y%m%d-%H%M%S).txt"
        generate_setup_report "$report_file" "$verify_status"
        success "Report saved to: $report_file"
        echo ""
    fi

    # Final messages
    echo "════════════════════════════════════════════════════════════════"
    echo "                    🎉 SETUP COMPLETED! 🎉                      "
    echo "════════════════════════════════════════════════════════════════"
    echo ""
    success "macOS setup finished successfully!"
    echo ""
    info "Recommended next steps:"
    echo "  1. Review the setup report on your Desktop"
    echo "  2. Restart your Mac to apply all changes"
    echo "  3. Open a new terminal to activate ZSH configuration"
    echo "  4. Sign in to applications that require authentication"
    echo "  5. Configure 1Password SSH if not already done"
    echo ""

    # Restart prompt
    if [[ "$NO_RESTART" != true ]]; then
        warning "Some changes require a restart to take effect!"
        echo ""

        # Check if running in interactive shell
        if [[ ! -t 0 ]]; then
            # Non-interactive shell (CI/CD, cron, etc.)
            info "Non-interactive shell detected. Skipping restart prompt."
            info "Run with --no-restart flag to suppress this message."
            warning "Remember to restart your Mac to apply all changes!"
        else
            # Interactive shell - ask user
            if confirm "Restart the Mac now?" "n"; then
                info "Restarting in 10 seconds... (Ctrl+C to cancel)"
                sleep 10
                sudo reboot
            else
                info "Remember to restart your Mac later to apply all changes!"
            fi
        fi
    else
        warning "Remember to restart your Mac to apply all changes!"
    fi

    echo ""
}

main "$@"
