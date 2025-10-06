#!/bin/bash
# 06-macos.sh - Configure macOS system preferences
set -euo pipefail

# Source helper functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/modules/_functions.sh"

# Load system configuration
load_system_config

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "                    macOS System Preferences                    "
echo "════════════════════════════════════════════════════════════════"
echo ""

# Close System Preferences to prevent overriding
osascript -e 'tell application "System Preferences" to quit' 2>/dev/null || true

# Ask for administrator password
sudo -v

# Keep sudo alive and save PID for cleanup
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
SUDO_LOOP_PID=$!
# Cleanup function to kill sudo keep-alive loop (trap registered immediately)
cleanup() {
    local exit_code=$?
    if [[ -n "${SUDO_LOOP_PID:-}" ]]; then
        kill "$SUDO_LOOP_PID" 2>/dev/null || true
    fi
    exit "$exit_code"
}
trap cleanup EXIT INT TERM

# ════════════════════════════════════════════════════════════════
# CONFIGURATION VARIABLES
# ════════════════════════════════════════════════════════════════
# You can override these by setting environment variables before running the script

# General Settings
COMPUTER_NAME="${COMPUTER_NAME:-Home-MacBookPro-Cloud}"
TIMEZONE="${TIMEZONE:-Europe/Kyiv}"

# UI/UX Preferences
SIDEBAR_ICON_SIZE="${SIDEBAR_ICON_SIZE:-1}"  # 1=small, 2=medium, 3=large

# Display & Screen
DISPLAY_SLEEP_MINUTES="${DISPLAY_SLEEP_MINUTES:-10}"
FONT_SMOOTHING="${FONT_SMOOTHING:-2}"  # 1=light, 2=medium, 3=strong

# Energy Saving
COMPUTER_SLEEP_BATTERY="${COMPUTER_SLEEP_BATTERY:-5}"  # Minutes on battery (0=never)
COMPUTER_SLEEP_POWER="${COMPUTER_SLEEP_POWER:-0}"      # Minutes on power (0=never)

# Hot Corners
# Values: 0=no-op, 2=Mission Control, 3=Application windows, 4=Desktop,
#         5=Start screensaver, 10=Sleep display, 11=Launchpad,
#         12=Notification Center, 13=Lock Screen
HOT_CORNER_TL="${HOT_CORNER_TL:-3}"    # Top left: Application windows
HOT_CORNER_TR="${HOT_CORNER_TR:-12}"   # Top right: Notification Center
HOT_CORNER_BL="${HOT_CORNER_BL:-13}"   # Bottom left: Lock Screen
HOT_CORNER_BR="${HOT_CORNER_BR:-11}"   # Bottom right: Launchpad

# ════════════════════════════════════════════════════════════════
# GENERAL UI/UX
# ════════════════════════════════════════════════════════════════
title "General UI/UX"

step "Setting computer name: $COMPUTER_NAME"
sudo scutil --set ComputerName "$COMPUTER_NAME"
sudo scutil --set HostName "$COMPUTER_NAME"
sudo scutil --set LocalHostName "$COMPUTER_NAME"
sudo defaults write /Library/Preferences/SystemConfiguration/com.apple.smb.server NetBIOSName -string "$COMPUTER_NAME"

step "Disabling startup sound"
if ! sudo nvram SystemAudioVolume=" " 2>/dev/null; then
  echo "Warning: Failed to disable startup sound using nvram." >&2
fi

step "Setting sidebar icon size: $SIDEBAR_ICON_SIZE"
defaults write NSGlobalDomain NSTableViewDefaultSizeMode -int "$SIDEBAR_ICON_SIZE"

step "Expanding save and print panels"
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool true
defaults write NSGlobalDomain PMPrintingExpandedStateForPrint -bool true
defaults write NSGlobalDomain PMPrintingExpandedStateForPrint2 -bool true

step "Auto-quit Printer app when jobs complete"
defaults write com.apple.print.PrintingPrefs "Quit When Finished" -bool true

step "Disabling quarantine warning for new apps"
defaults write com.apple.LaunchServices LSQuarantine -bool false

step "Displaying ASCII control characters"
defaults write NSGlobalDomain NSTextShowsControlCharacters -bool true

step "Help Viewer in standard window mode"
defaults write com.apple.helpviewer DevMode -bool true

step "Smart dashes and quotes (enabled)"
defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool true
defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool true

step "Disabling auto-correct"
defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false

# ════════════════════════════════════════════════════════════════
# TRACKPAD, MOUSE, KEYBOARD
# ════════════════════════════════════════════════════════════════
title "Trackpad, Mouse, Keyboard"

step "Improving Bluetooth audio quality"
defaults write com.apple.BluetoothAudioAgent "Apple Bitpool Min (editable)" -int 40

step "Enable full keyboard access for all controls"
defaults write NSGlobalDomain AppleKeyboardUIMode -int 3

# ════════════════════════════════════════════════════════════════
# LANGUAGE & REGION
# ════════════════════════════════════════════════════════════════
title "Language & Region"

# Allow language, locale, and measurement units to be set via environment variables, with defaults
LANGUAGES="${MACOS_LANGUAGES:-en-US uk-UA}"
LOCALE="${MACOS_LOCALE:-en_US@currency=UAH}"
MEASUREMENT_UNITS="${MACOS_MEASUREMENT_UNITS:-Centimeters}"

# Sanitize LANGUAGES: trim leading/trailing whitespace and collapse multiple spaces
LANGUAGES="$(echo "$LANGUAGES" | xargs)"

# Validate language codes (BCP47: letters, digits, hyphens, underscores, spaces)
regex='^[a-zA-Z0-9_ -]+$'
if ! [[ "$LANGUAGES" =~ $regex ]]; then
  warning "LANGUAGES contains invalid characters. Resetting to default."
  LANGUAGES="en-US uk-UA"
fi

step "Setting system language"
# Convert space-separated string to array for proper defaults write
IFS=' ' read -ra LANG_ARRAY <<< "$LANGUAGES"
defaults write NSGlobalDomain AppleLanguages -array "${LANG_ARRAY[@]}"
defaults write NSGlobalDomain AppleLocale -string "$LOCALE"
defaults write NSGlobalDomain AppleMeasurementUnits -string "$MEASUREMENT_UNITS"
defaults write NSGlobalDomain AppleMetricUnits -bool true

step "Setting timezone: $TIMEZONE"
sudo systemsetup -settimezone "$TIMEZONE" > /dev/null

# ════════════════════════════════════════════════════════════════
# ENERGY SAVING
# ════════════════════════════════════════════════════════════════
title "Energy Saving"

step "Configuring energy saver settings"
sudo pmset -a lidwake 1                    # Wake when lid opens
# sudo pmset -a autorestart 1              # Skip enabling auto restart after power loss (per preference)
sudo systemsetup -setrestartfreeze on      # Restart on freeze

step "Setting display sleep to $DISPLAY_SLEEP_MINUTES minutes"
sudo pmset -a displaysleep "$DISPLAY_SLEEP_MINUTES"

step "Setting computer sleep"
sudo pmset -c sleep "$COMPUTER_SLEEP_POWER"      # On AC power
sudo pmset -b sleep "$COMPUTER_SLEEP_BATTERY"    # On battery

# ════════════════════════════════════════════════════════════════
# SCREEN
# ════════════════════════════════════════════════════════════════
title "Screen"

# Font smoothing settings (Intel only - ignored on Apple Silicon Retina displays)
if ! sysctl -n machdep.cpu.brand_string 2>/dev/null | grep -q "Apple"; then
    step "Subpixel antialiasing (Intel only)"
    defaults write -g CGFontRenderingFontSmoothingDisabled -bool FALSE

    step "Font smoothing (medium)"
    defaults write NSGlobalDomain AppleFontSmoothing -int "$FONT_SMOOTHING"
else
    warning "Font smoothing settings skipped (not applicable on Apple Silicon)"
fi

step "Require password immediately after sleep"
defaults write com.apple.screensaver askForPassword -int 1
defaults write com.apple.screensaver askForPasswordDelay -int 0

# ════════════════════════════════════════════════════════════════
# FINDER
# ════════════════════════════════════════════════════════════════
title "Finder"

# step "Disable Finder animations" # Intentionally left disabled per preference
# defaults write com.apple.finder DisableAllAnimations -bool true

step "Show path bar"
defaults write com.apple.finder ShowPathbar -bool true

step "Keep folders on top when sorting"
defaults write com.apple.finder _FXSortFoldersFirst -bool true

step "Search current folder by default"
defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"

step "Disable warning when changing file extension"
defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false

step "Avoid creating .DS_Store on network and USB volumes"
defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true

step "List view by default"
defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"

# step "Disable trash empty warning" # Left as-is per preference
# defaults write com.apple.finder WarnOnEmptyTrash -bool false

step "Show ~/Library"
chflags nohidden ~/Library 2>/dev/null
chflags_status=$?
xattr -d com.apple.FinderInfo ~/Library 2>/dev/null
xattr_status=$?
if [[ $chflags_status -ne 0 || $xattr_status -ne 0 ]]; then
    warning "$HOME/Library may still be hidden or have unwanted attributes (failed to run chflags or xattr)"
fi

step "Configure desktop icon layout"
FINDER_PLIST="$HOME/Library/Preferences/com.apple.finder.plist"

if [[ ! -f "$FINDER_PLIST" ]]; then
    warning "Finder preferences not found yet (will be created on first Finder launch)"
else
    # Desktop icon layout
    if /usr/libexec/PlistBuddy -c "Print :DesktopViewSettings:IconViewSettings:arrangeBy" "$FINDER_PLIST" &>/dev/null; then
        if /usr/libexec/PlistBuddy -c "Set :DesktopViewSettings:IconViewSettings:arrangeBy grid" "$FINDER_PLIST" 2>/dev/null; then
            success "Desktop icon layout set to grid"
        else
            warning "Failed to set desktop icon layout"
        fi
    else
        warning "Desktop icon layout setting not available on this macOS version"
    fi

    # Standard view layout
    if /usr/libexec/PlistBuddy -c "Print :StandardViewSettings:IconViewSettings:arrangeBy" "$FINDER_PLIST" &>/dev/null; then
        if /usr/libexec/PlistBuddy -c "Set :StandardViewSettings:IconViewSettings:arrangeBy grid" "$FINDER_PLIST" 2>/dev/null; then
            success "Standard view layout set to grid"
        else
            warning "Failed to set standard view layout"
        fi
    else
        warning "Standard view layout setting not available on this macOS version"
    fi
fi

step "Expand key File Info panes"
defaults write com.apple.finder FXInfoPanesExpanded -dict \
    General -bool true \
    OpenWith -bool true \
    Privileges -bool true \
    Comments -bool true \
    MetaData -bool true \
    Name -bool true

step "Enable sidebar"
defaults write com.apple.finder FK_AppCentricShowSidebar -bool true

step "Set sidebar width"
defaults write com.apple.finder FK_SidebarWidth -int 149

step "Auto-remove old trash items after 30 days"
defaults write com.apple.finder FXRemoveOldTrashItems -bool true

step "Set Finder group by"
defaults write com.apple.finder FXArrangeGroupViewBy -string "Name"

step "Configure desktop icon view"
defaults write com.apple.finder DesktopViewSettings -dict \
    IconViewSettings -dict \
        iconSize -int 64 \
        gridSpacing -int 54 \
        arrangeBy -string "none" \
        showIconPreview -bool true \
        textSize -int 12 \
        labelOnBottom -bool true

step "Configure standard list view"
defaults write com.apple.finder FK_StandardViewSettings -dict \
    ListViewSettings -dict \
        iconSize -int 16 \
        textSize -int 13 \
        sortColumn -string "name" \
        useRelativeDates -bool true \
        showIconPreview -bool true

step "Enable iCloud Drive Desktop & Documents sync"
defaults write com.apple.finder FXICloudDriveDesktop -bool true
defaults write com.apple.finder FXICloudDriveDocuments -bool true
defaults write com.apple.finder FXICloudDriveEnabled -bool true

# ════════════════════════════════════════════════════════════════
# DOCK
# ════════════════════════════════════════════════════════════════
title "Dock"

step "Configuring Dock"
defaults write com.apple.dock mouse-over-hilite-stack -bool false   # Current preference
defaults write com.apple.dock mineffect -string "genie"             # Current preference
defaults write com.apple.dock minimize-to-application -bool true

step "Clearing Dock icons"
defaults write com.apple.dock persistent-apps -array

# Autohide intentionally disabled per preference
# defaults write com.apple.dock autohide -bool false

step "Hide recent applications"
defaults write com.apple.dock show-recents -bool false

step "Configuring hot corners"
defaults write com.apple.dock wvous-tl-corner -int "$HOT_CORNER_TL"
defaults write com.apple.dock wvous-tl-modifier -int 0
defaults write com.apple.dock wvous-tr-corner -int "$HOT_CORNER_TR"
defaults write com.apple.dock wvous-tr-modifier -int 0
defaults write com.apple.dock wvous-bl-corner -int "$HOT_CORNER_BL"
defaults write com.apple.dock wvous-bl-modifier -int 0
defaults write com.apple.dock wvous-br-corner -int "$HOT_CORNER_BR"
defaults write com.apple.dock wvous-br-modifier -int 0

# ════════════════════════════════════════════════════════════════
# SAFARI & WEBKIT
# ════════════════════════════════════════════════════════════════
title "Safari"

step "Configuring Safari"
defaults write com.apple.Safari UniversalSearchEnabled -bool false
defaults write com.apple.Safari SuppressSearchSuggestions -bool true
defaults write com.apple.Safari ShowFullURLInSmartSearchField -bool true
defaults write com.apple.Safari WarnAboutFraudulentWebsites -bool true
defaults write com.apple.Safari IncludeDevelopMenu -bool true
defaults write com.apple.Safari WebKitDeveloperExtrasEnabledPreferenceKey -bool true
defaults write com.apple.Safari com.apple.Safari.ContentPageGroupIdentifier.WebKit2DeveloperExtrasEnabled -bool true
defaults write com.apple.Safari InstallExtensionUpdatesAutomatically -bool true

# ════════════════════════════════════════════════════════════════
# TERMINAL & ITERM
# ════════════════════════════════════════════════════════════════
title "Terminal"

step "Force UTF-8 in Terminal"
defaults write com.apple.terminal StringEncodings -array 4

if [[ -d "/Applications/iTerm.app" ]]; then
    step "Disable confirm prompt when quitting iTerm"
    defaults write com.googlecode.iterm2 PromptOnQuit -bool false
fi

# ════════════════════════════════════════════════════════════════
# TIME MACHINE
# ════════════════════════════════════════════════════════════════
title "Time Machine"

step "Prevent Time Machine from offering new disks"
defaults write com.apple.TimeMachine DoNotOfferNewDisksForBackup -bool true

# ════════════════════════════════════════════════════════════════
# ACTIVITY MONITOR
# ════════════════════════════════════════════════════════════════
title "Activity Monitor"

step "Configuring Activity Monitor"
defaults write com.apple.ActivityMonitor OpenMainWindow -bool true
# defaults write com.apple.ActivityMonitor IconType -int 5  # Keeping existing preference
# defaults write com.apple.ActivityMonitor ShowCategory -int 0  # Keeping existing preference

# ════════════════════════════════════════════════════════════════
# MAC APP STORE
# ════════════════════════════════════════════════════════════════
title "Mac App Store"

step "Enable automatic updates"
defaults write com.apple.SoftwareUpdate AutomaticCheckEnabled -bool true
defaults write com.apple.SoftwareUpdate ScheduleFrequency -int 1
defaults write com.apple.SoftwareUpdate AutomaticDownload -int 1
defaults write com.apple.SoftwareUpdate CriticalUpdateInstall -int 1
defaults write com.apple.commerce AutoUpdate -bool true

# ════════════════════════════════════════════════════════════════
# PHOTOS
# ════════════════════════════════════════════════════════════════
title "Photos"

step "Stop Photos from auto-launching"
defaults -currentHost write com.apple.ImageCapture disableHotPlug -bool true

# ════════════════════════════════════════════════════════════════
# TRANSMISSION
# ════════════════════════════════════════════════════════════════
if [[ -d "/Applications/Transmission.app" ]]; then
    title "Transmission"

    step "Configuring Transmission"
    defaults write org.m0k.transmission UseIncompleteDownloadFolder -bool true
    defaults write org.m0k.transmission IncompleteDownloadFolder -string "${HOME}/Downloads/Torrents"
    defaults write org.m0k.transmission DownloadLocationConstant -bool true
    defaults write org.m0k.transmission DownloadAsk -bool false
    defaults write org.m0k.transmission MagnetOpenAsk -bool false
    defaults write org.m0k.transmission CheckRemoveDownloading -bool true
    defaults write org.m0k.transmission DeleteOriginalTorrent -bool true
    defaults write org.m0k.transmission WarningDonate -bool false
    defaults write org.m0k.transmission WarningLegal -bool false
    defaults write org.m0k.transmission BlocklistNew -bool true
    defaults write org.m0k.transmission BlocklistURL -string "http://john.bitsurge.net/public/biglist.p2p.gz"
    defaults write org.m0k.transmission BlocklistAutoUpdate -bool true
    defaults write org.m0k.transmission RandomPort -bool true
fi

# ════════════════════════════════════════════════════════════════
# KILL AFFECTED APPLICATIONS
# ════════════════════════════════════════════════════════════════
title "Restart affected applications"

for app in \
    "Activity Monitor" \
    "cfprefsd" \
    "Dock" \
    "Finder" \
    "Safari" \
    "SystemUIServer"; do
    killall "${app}" &> /dev/null || true
done

echo ""
success "macOS configuration complete!"
warning "Some changes require a system restart"
warning "Please restart Terminal manually to apply all changes"
echo ""