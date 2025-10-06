#!/bin/bash
# 00-cleanup-state.sh - Clean up previous setup state for fresh start
set -euo pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Helper functions
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }
warning() { echo -e "${YELLOW}[⚠]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1" >&2; }
step() { echo -e "${CYAN}[→]${NC} $1"; }

echo ""
echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
echo -e "${BOLD}            Cleanup Previous Setup State                        ${NC}"
echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
echo ""

warning "This will remove all traces of previous setup runs"
info "You'll be able to start completely fresh"
echo ""

# List what will be cleaned
info "Will clean:"
echo "  • Completed modules tracking"
echo "  • Setup session timestamps"
echo "  • System configuration cache"
echo "  • Hanging sudo keepalive processes"
echo "  • Temporary files"
echo ""

if [[ -t 0 ]]; then
    read -p "$(echo -e "${YELLOW}Proceed with cleanup? [y/N]:${NC} ")" -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        info "Cleanup cancelled"
        exit 0
    fi
else
    info "Non-interactive shell detected. Cleanup cancelled."
    exit 0
fi

echo ""
step "Cleaning setup state files..."

# Remove tracking files
if [[ -f "$SCRIPT_DIR/.completed_modules" ]]; then
    rm -f "$SCRIPT_DIR/.completed_modules"
    success "Removed: .completed_modules"
fi

if [[ -f "$SCRIPT_DIR/.setup_session" ]]; then
    rm -f "$SCRIPT_DIR/.setup_session"
    success "Removed: .setup_session"
fi

if [[ -f "$SCRIPT_DIR/config/system.conf" ]]; then
    rm -f "$SCRIPT_DIR/config/system.conf"
    success "Removed: config/system.conf"
fi

# Kill any hanging sudo keepalive processes
step "Checking for hanging processes..."
shopt -s nullglob
KILLED_COUNT=0
for pid_file in /tmp/macos-setup-sudo-*; do
    if [[ -f "$pid_file" ]]; then
        PID=$(cat "$pid_file" 2>/dev/null || echo "")
        if [[ -n "$PID" ]] && kill -0 "$PID" 2>/dev/null; then
            kill "$PID" 2>/dev/null || true
            KILLED_COUNT=$((KILLED_COUNT + 1))
        fi
        rm -f "$pid_file"
    fi
done
shopt -u nullglob

if [[ $KILLED_COUNT -gt 0 ]]; then
    success "Killed $KILLED_COUNT hanging sudo keepalive process(es)"
else
    info "No hanging processes found"
fi

# Remove temp files
step "Cleaning temporary files..."
rm -f /tmp/macos-setup-* 2>/dev/null || true
success "Temporary files cleaned"

echo ""
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
success "Cleanup complete! Ready for fresh setup."
echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
echo ""
info "You can now run: ./fresh-new.sh"
echo ""
