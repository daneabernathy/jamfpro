#!/bin/bash
# PaperCut Print Deploy - Full Removal Script
# Deploy via Jamf Pro. Removes the Print Deploy client, all deployed printers
# matching known suffixes, and all PaperCut-related preference files system-wide.
# Intended for use during a PaperCut server migration.

###############################################################################
# CONFIGURATION
###############################################################################

# Suffixes of printer names deployed by PaperCut Print Deploy.
# Add or remove entries to match your environment.
PRINTER_SUFFIXES=(
    "-papercut"
    "_papercut"
    "-printdeploy"
    "_printdeploy"
    "-pcd"
    "_pcd"
)

# Known PaperCut Print Deploy app locations
PRINT_DEPLOY_APP="/Applications/PCClient.app"
PRINT_DEPLOY_ALT="/Applications/PaperCut Print Deploy Client.app"
PRINT_DEPLOY_FOLDER="/Applications/PaperCut Print Deploy"

# Uninstall script candidates (tries each in order, stops at first found)
UNINSTALL_CANDIDATES=(
    "/Applications/PaperCut Print Deploy/uninstall.command"
    "/Applications/PCClient.app/Contents/Resources/uninstall.command"
    "/Applications/PaperCut Print Deploy Client.app/Contents/Resources/uninstall.command"
)

# PaperCut bundle/domain identifiers used to locate preference files
PAPERCUT_BUNDLE_IDS=(
    "com.papercut.printdeploy"
    "com.papercut.client"
    "com.papercut.PCClient"
    "net.papercut"
    "com.papercut"
)

# System-level preference directories to scan
SYSTEM_PREF_DIRS=(
    "/Library/Preferences"
    "/Library/Managed Preferences"
    "/private/var/root/Library/Preferences"
)

###############################################################################
# HELPERS
###############################################################################

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

remove_path() {
    local target="$1"
    if [ -e "$target" ] || [ -L "$target" ]; then
        rm -rf "$target" && log "  Removed: $target" || log "  WARNING: Failed to remove: $target"
    fi
}

###############################################################################
# 1. UNINSTALL PRINT DEPLOY CLIENT
###############################################################################

log "=== Step 1: Uninstalling PaperCut Print Deploy Client ==="

UNINSTALL_RAN=false
for script in "${UNINSTALL_CANDIDATES[@]}"; do
    if [ -f "$script" ]; then
        log "Found uninstall script: $script"
        chmod +x "$script"
        bash "$script" &>/dev/null
        exit_code=$?
        if [ $exit_code -eq 0 ]; then
            log "Uninstall script completed successfully."
        else
            log "WARNING: Uninstall script exited with code $exit_code — continuing with manual cleanup."
        fi
        UNINSTALL_RAN=true
        break
    fi
done

if [ "$UNINSTALL_RAN" = false ]; then
    log "No uninstall script found — proceeding with manual removal only."
fi

# Stop any running PaperCut processes
for proc in "PCClient" "PaperCut Print Deploy" "pc-client" "papercut-client"; do
    if pgrep -f "$proc" &>/dev/null; then
        log "Stopping process: $proc"
        pkill -f "$proc" 2>/dev/null
        sleep 1
        pkill -9 -f "$proc" 2>/dev/null
    fi
done

# Remove application bundles and install folders
for app_path in "$PRINT_DEPLOY_APP" "$PRINT_DEPLOY_ALT" "$PRINT_DEPLOY_FOLDER"; do
    remove_path "$app_path"
done

# Unload and remove system-level LaunchDaemons and LaunchAgents
for launch_dir in /Library/LaunchDaemons /Library/LaunchAgents; do
    for plist in "$launch_dir"/com.papercut.* "$launch_dir"/net.papercut.*; do
        [ -f "$plist" ] || continue
        label=$(defaults read "$plist" Label 2>/dev/null)
        if [ -n "$label" ]; then
            launchctl bootout system/"$label" 2>/dev/null
            launchctl remove "$label" 2>/dev/null
        fi
        remove_path "$plist"
    done
done

# Unload and remove per-user LaunchAgents
while IFS= read -r user_home; do
    la_dir="$user_home/Library/LaunchAgents"
    [ -d "$la_dir" ] || continue
    for plist in "$la_dir"/com.papercut.* "$la_dir"/net.papercut.*; do
        [ -f "$plist" ] || continue
        uid=$(stat -f "%u" "$user_home" 2>/dev/null)
        label=$(defaults read "$plist" Label 2>/dev/null)
        if [ -n "$label" ] && [ -n "$uid" ]; then
            launchctl bootout gui/"$uid"/"$label" 2>/dev/null
        fi
        remove_path "$plist"
    done
done < <(find /Users -maxdepth 1 -mindepth 1 -type d ! -name "Shared" ! -name ".localized" 2>/dev/null)

###############################################################################
# 2. REMOVE PRINTERS MATCHING SUFFIX LIST
###############################################################################

log "=== Step 2: Removing PaperCut-deployed printers ==="

while IFS= read -r printer; do
    printer_lower=$(echo "$printer" | tr '[:upper:]' '[:lower:]')
    for suffix in "${PRINTER_SUFFIXES[@]}"; do
        suffix_lower=$(echo "$suffix" | tr '[:upper:]' '[:lower:]')
        if [[ "$printer_lower" == *"$suffix_lower" ]]; then
            log "Removing printer: $printer"
            lpadmin -x "$printer" && log "  Done." || log "  WARNING: lpadmin failed for $printer"
            break
        fi
    done
done < <(lpstat -p 2>/dev/null | awk '/^printer/ {print $2}')

###############################################################################
# 3. REMOVE PREFERENCE FILES (SYSTEM, MANAGED, AND PER-USER)
###############################################################################

log "=== Step 3: Removing PaperCut preference files ==="

# Build an extended regex pattern from bundle IDs for grep matching
PREF_PATTERN=$(IFS="|"; echo "${PAPERCUT_BUNDLE_IDS[*]}")

# -- System-level and Managed Preferences --
for pref_dir in "${SYSTEM_PREF_DIRS[@]}"; do
    [ -d "$pref_dir" ] || continue

    # Top-level plists directly in the directory
    while IFS= read -r plist; do
        remove_path "$plist"
    done < <(find "$pref_dir" -maxdepth 1 -type f -name "*.plist" 2>/dev/null | grep -E "$PREF_PATTERN")

    # Subdirectories — e.g. /Library/Managed Preferences/<username>/
    # These contain per-user managed plists pushed via MDM profiles
    while IFS= read -r subdir; do
        while IFS= read -r plist; do
            remove_path "$plist"
        done < <(find "$subdir" -maxdepth 1 -type f -name "*.plist" 2>/dev/null | grep -E "$PREF_PATTERN")
    done < <(find "$pref_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
done

# -- Per-user preferences, caches, and application support --
while IFS= read -r user_home; do
    username=$(basename "$user_home")

    # ~/Library/Preferences — remove only matching plists
    pref_dir="$user_home/Library/Preferences"
    if [ -d "$pref_dir" ]; then
        while IFS= read -r plist; do
            remove_path "$plist"
        done < <(find "$pref_dir" -maxdepth 1 -type f -name "*.plist" 2>/dev/null | grep -E "$PREF_PATTERN")
    fi

    # Named folders that belong entirely to PaperCut — remove whole directory
    for named_dir in \
        "$user_home/Library/Application Support/PaperCut" \
        "$user_home/Library/Application Support/PCClient" \
        "$user_home/Library/Application Support/PaperCut Print Deploy" \
        "$user_home/Library/Caches/com.papercut.printdeploy" \
        "$user_home/Library/Caches/com.papercut.client" \
        "$user_home/Library/Caches/PCClient"
    do
        remove_path "$named_dir"
    done

    log "  Cleaned preferences for user: $username"
done < <(find /Users -maxdepth 1 -mindepth 1 -type d ! -name "Shared" ! -name ".localized" 2>/dev/null)

# Flush cfprefsd so removed plists are not served from the in-memory cache
killall cfprefsd 2>/dev/null || true

###############################################################################
# 4. REMOVE ADDITIONAL SYSTEM ARTIFACTS
###############################################################################

log "=== Step 4: Removing additional PaperCut artifacts ==="

for artifact in \
    "/Library/Application Support/PaperCut" \
    "/Library/Application Support/PCClient" \
    "/private/tmp/papercut" \
    "/private/tmp/PCClient" \
    "/var/log/papercut-client.log"
do
    remove_path "$artifact"
done

###############################################################################
# DONE
###############################################################################

log "=== PaperCut Print Deploy removal complete. ==="
log "The device is ready to receive the new Print Deploy installer."
exit 0
`
