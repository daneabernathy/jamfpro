#!/bin/bash
# PaperCut Print Deploy - Full Removal Script
# Deploy via Jamf Pro. Removes the Print Deploy client, all deployed printers
# matching known prefixes, and all PaperCut Print Deploy-related preference files.
# Intended for use during a PaperCut server migration.
# Note: PCClient (Mobility Print) is handled by a separate script.

###############################################################################
# CONFIGURATION
###############################################################################

# prefixes of printer names deployed by PaperCut Print Deploy.
# Add or remove entries to match your environment.

PRINTER_PREFIXES=(
    "alumni"
    "ransom"
    "goodyear"
    "hawkins"
    "crawford"
    "wilson"
    "dodge"
    "patterson"
    "gerard"
    "library"
    "museum"
    "juckett"
    "partridge"
    "bartoletto"
    "cabot"
    "tompkins"
    "ssc"
    "schneider"
    "public"
    "ainsworth"
    "andrews"
    "chaplin"
    "communications"
    "guidon"
    "dewey"
    "flint"
    "ellis"
    "nuari"
    "osp"
    "wise"
    "hayden"
    "construction"
    "hollis"
    "jackman"
    "arena"
    "armory"
    "plumley"
    "roberts"
    "chapel"
    "south"
    "darlyrimple"
    "mack"
    "brother"
    "secure"
    "epilog"
    "konica"
    "lexmark"
    "green"
    "hassett"
    "north"
    "print"
    "barteletto"
)

# Known PaperCut Print Deploy app location
PRINT_DEPLOY_APP="/Applications/PaperCut Print Deploy Client"

# Uninstall script location
UNINSTALL_SCRIPT="/Applications/PaperCut Print Deploy Client/Uninstall.command"

# Print Deploy bundle identifier
PAPERCUT_BUNDLE_ID="com.papercut.printdeploy"

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

if [ -f "$UNINSTALL_SCRIPT" ]; then
    log "Found uninstall script: $UNINSTALL_SCRIPT"
    chmod +x "$UNINSTALL_SCRIPT"
    bash "$UNINSTALL_SCRIPT" -y &>/dev/null
    exit_code=$?
    if [ $exit_code -eq 0 ]; then
        log "Uninstall script completed successfully."
    else
        log "WARNING: Uninstall script exited with code $exit_code — continuing with manual cleanup."
    fi
else
    log "No uninstall script found — proceeding with manual removal only."
fi

# Stop any running Print Deploy processes
for proc in "pc-print-deploy-client" "PaperCut Print Deploy"; do
    if pgrep -f "$proc" &>/dev/null; then
        log "Stopping process: $proc"
        pkill -f "$proc" 2>/dev/null
        sleep 1
        pkill -9 -f "$proc" 2>/dev/null
    fi
done

# Remove application folder (includes direct-print-monitor subfolder)
remove_path "$PRINT_DEPLOY_APP"

# Unload and remove the known LaunchAgent
LAUNCH_AGENT_SYSTEM="/Library/LaunchAgents/com.papercut.printdeploy.client.plist"
if [ -f "$LAUNCH_AGENT_SYSTEM" ]; then
    label=$(defaults read "$LAUNCH_AGENT_SYSTEM" Label 2>/dev/null)
    [ -n "$label" ] && launchctl bootout system/"$label" 2>/dev/null
    [ -n "$label" ] && launchctl remove "$label" 2>/dev/null
    remove_path "$LAUNCH_AGENT_SYSTEM"
fi

# Unload and remove per-user LaunchAgents
while IFS= read -r user_home; do
    plist="$user_home/Library/LaunchAgents/com.papercut.printdeploy.client.plist"
    [ -f "$plist" ] || continue
    uid=$(stat -f "%u" "$user_home" 2>/dev/null)
    label=$(defaults read "$plist" Label 2>/dev/null)
    if [ -n "$label" ] && [ -n "$uid" ]; then
        launchctl bootout gui/"$uid"/"$label" 2>/dev/null
    fi
    remove_path "$plist"
done < <(find /Users -maxdepth 1 -mindepth 1 -type d ! -name "Shared" ! -name ".localized" 2>/dev/null)

###############################################################################
# 2. REMOVE PRINTERS MATCHING prefix LIST
###############################################################################

log "=== Step 2: Removing PaperCut-deployed printers ==="

ALL_PRINTERS=()
while IFS= read -r line; do
    ALL_PRINTERS+=("$line")
done < <(lpstat -a 2>/dev/null | awk '{print $1}')

if [ ${#ALL_PRINTERS[@]} -eq 0 ]; then
    log "No printers found via lpstat"
else
    log "Found ${#ALL_PRINTERS[@]} printer(s): ${ALL_PRINTERS[*]}"
    for printer in "${ALL_PRINTERS[@]}"; do
        printer_lower=$(echo "$printer" | tr '[:upper:]' '[:lower:]')
        matched=false
        for prefix in "${PRINTER_PREFIXES[@]}"; do
            prefix_lower=$(echo "$prefix" | tr '[:upper:]' '[:lower:]')
            if [[ "$printer_lower" == "$prefix_lower"* ]]; then
                matched=true
                log "Removing printer: $printer"
                if lpadmin -x "$printer" 2>/dev/null; then
                    log "  Successfully removed: $printer"
                else
                    log "  WARNING: lpadmin failed to remove: $printer (exit code $?)"
                fi
                break
            fi
        done
        if [ "$matched" = false ]; then
            log "  Skipping (no matching prefix): $printer"
        fi
    done
fi

###############################################################################
# 3. REMOVE PREFERENCE FILES (SYSTEM, MANAGED, AND PER-USER)
###############################################################################

log "=== Step 3: Removing PaperCut Print Deploy preference files ==="

# -- System-level and Managed Preferences --
for pref_dir in "${SYSTEM_PREF_DIRS[@]}"; do
    [ -d "$pref_dir" ] || continue

    # Top-level plists
    while IFS= read -r plist; do
        remove_path "$plist"
    done < <(find "$pref_dir" -maxdepth 1 -type f -name "${PAPERCUT_BUNDLE_ID}*.plist" 2>/dev/null)

    # Subdirectories — e.g. /Library/Managed Preferences/<username>/
    while IFS= read -r subdir; do
        while IFS= read -r plist; do
            remove_path "$plist"
        done < <(find "$subdir" -maxdepth 1 -type f -name "${PAPERCUT_BUNDLE_ID}*.plist" 2>/dev/null)
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
        done < <(find "$pref_dir" -maxdepth 1 -type f -name "${PAPERCUT_BUNDLE_ID}*.plist" 2>/dev/null)
    fi

    # Named folders that belong entirely to Print Deploy
    for named_dir in \
        "$user_home/Library/Application Support/PaperCut Print Deploy" \
        "$user_home/Library/Application Support/PaperCut Print Deploy Client" \
        "$user_home/Library/Application Support/PapercutPrintDeployClient" \
        "$user_home/Library/Caches/com.papercut.printdeploy"
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

log "=== Step 4: Removing additional Print Deploy artifacts ==="

# Remove package receipts so macOS doesn't block reinstalling older versions
for receipt in /private/var/db/receipts/com.papercut.printdeploy.client.*; do
    remove_path "$receipt"
done

###############################################################################
# DONE
###############################################################################

log "=== PaperCut Print Deploy removal complete. ==="
log "The device is ready to receive the new Print Deploy installer."
exit 0

)

# Known PaperCut Print Deploy app location
PRINT_DEPLOY_APP="/Applications/PaperCut Print Deploy Client"

# Uninstall script location
UNINSTALL_SCRIPT="/Applications/PaperCut Print Deploy Client/Uninstall.command"

# Print Deploy bundle identifier
PAPERCUT_BUNDLE_ID="com.papercut.printdeploy"

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

if [ -f "$UNINSTALL_SCRIPT" ]; then
    log "Found uninstall script: $UNINSTALL_SCRIPT"
    chmod +x "$UNINSTALL_SCRIPT"
    bash "$UNINSTALL_SCRIPT" -y &>/dev/null
    exit_code=$?
    if [ $exit_code -eq 0 ]; then
        log "Uninstall script completed successfully."
    else
        log "WARNING: Uninstall script exited with code $exit_code — continuing with manual cleanup."
    fi
else
    log "No uninstall script found — proceeding with manual removal only."
fi

# Stop any running Print Deploy processes
for proc in "pc-print-deploy-client" "PaperCut Print Deploy"; do
    if pgrep -f "$proc" &>/dev/null; then
        log "Stopping process: $proc"
        pkill -f "$proc" 2>/dev/null
        sleep 1
        pkill -9 -f "$proc" 2>/dev/null
    fi
done

# Remove application folder (includes direct-print-monitor subfolder)
remove_path "$PRINT_DEPLOY_APP"

# Unload and remove the known LaunchAgent
LAUNCH_AGENT_SYSTEM="/Library/LaunchAgents/com.papercut.printdeploy.client.plist"
if [ -f "$LAUNCH_AGENT_SYSTEM" ]; then
    label=$(defaults read "$LAUNCH_AGENT_SYSTEM" Label 2>/dev/null)
    [ -n "$label" ] && launchctl bootout system/"$label" 2>/dev/null
    [ -n "$label" ] && launchctl remove "$label" 2>/dev/null
    remove_path "$LAUNCH_AGENT_SYSTEM"
fi

# Unload and remove per-user LaunchAgents
while IFS= read -r user_home; do
    plist="$user_home/Library/LaunchAgents/com.papercut.printdeploy.client.plist"
    [ -f "$plist" ] || continue
    uid=$(stat -f "%u" "$user_home" 2>/dev/null)
    label=$(defaults read "$plist" Label 2>/dev/null)
    if [ -n "$label" ] && [ -n "$uid" ]; then
        launchctl bootout gui/"$uid"/"$label" 2>/dev/null
    fi
    remove_path "$plist"
done < <(find /Users -maxdepth 1 -mindepth 1 -type d ! -name "Shared" ! -name ".localized" 2>/dev/null)

###############################################################################
# 2. REMOVE PRINTERS MATCHING prefix LIST
###############################################################################

log "=== Step 2: Removing PaperCut-deployed printers ==="

ALL_PRINTERS=()
while IFS= read -r line; do
    ALL_PRINTERS+=("$line")
done < <(lpstat -a 2>/dev/null | awk '{print $1}')

if [ ${#ALL_PRINTERS[@]} -eq 0 ]; then
    log "No printers found via lpstat"
else
    log "Found ${#ALL_PRINTERS[@]} printer(s): ${ALL_PRINTERS[*]}"
    for printer in "${ALL_PRINTERS[@]}"; do
        printer_lower=$(echo "$printer" | tr '[:upper:]' '[:lower:]')
        matched=false
        for prefix in "${PRINTER_PREFIXES[@]}"; do
            prefix_lower=$(echo "$prefix" | tr '[:upper:]' '[:lower:]')
            if [[ "$printer_lower" == "$prefix_lower"* ]]; then
                matched=true
                log "Removing printer: $printer"
                if lpadmin -x "$printer" 2>/dev/null; then
                    log "  Successfully removed: $printer"
                else
                    log "  WARNING: lpadmin failed to remove: $printer (exit code $?)"
                fi
                break
            fi
        done
        if [ "$matched" = false ]; then
            log "  Skipping (no matching prefix): $printer"
        fi
    done
fi

###############################################################################
# 3. REMOVE PREFERENCE FILES (SYSTEM, MANAGED, AND PER-USER)
###############################################################################

log "=== Step 3: Removing PaperCut Print Deploy preference files ==="

# -- System-level and Managed Preferences --
for pref_dir in "${SYSTEM_PREF_DIRS[@]}"; do
    [ -d "$pref_dir" ] || continue

    # Top-level plists
    while IFS= read -r plist; do
        remove_path "$plist"
    done < <(find "$pref_dir" -maxdepth 1 -type f -name "${PAPERCUT_BUNDLE_ID}*.plist" 2>/dev/null)

    # Subdirectories — e.g. /Library/Managed Preferences/<username>/
    while IFS= read -r subdir; do
        while IFS= read -r plist; do
            remove_path "$plist"
        done < <(find "$subdir" -maxdepth 1 -type f -name "${PAPERCUT_BUNDLE_ID}*.plist" 2>/dev/null)
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
        done < <(find "$pref_dir" -maxdepth 1 -type f -name "${PAPERCUT_BUNDLE_ID}*.plist" 2>/dev/null)
    fi

    # Named folders that belong entirely to Print Deploy
    for named_dir in \
        "$user_home/Library/Application Support/PaperCut Print Deploy" \
        "$user_home/Library/Application Support/PaperCut Print Deploy Client" \
        "$user_home/Library/Application Support/PapercutPrintDeployClient" \
        "$user_home/Library/Caches/com.papercut.printdeploy"
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

log "=== Step 4: Removing additional Print Deploy artifacts ==="

# Remove package receipts so macOS doesn't block reinstalling older versions
for receipt in /private/var/db/receipts/com.papercut.printdeploy.client.*; do
    remove_path "$receipt"
done

###############################################################################
# DONE
###############################################################################

log "=== PaperCut Print Deploy removal complete. ==="
log "The device is ready to receive the new Print Deploy installer."
exit 0
