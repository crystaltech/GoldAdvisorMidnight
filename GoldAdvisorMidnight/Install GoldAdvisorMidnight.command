#!/bin/bash

set -euo pipefail

ADDON_NAME="GoldAdvisorMidnight"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEFAULT_ADDONS_DIR="/Applications/World of Warcraft/_retail_/Interface/AddOns"

pause_on_exit() {
    if [ -t 0 ]; then
        printf "\nPress Return to close..."
        read -r _gam_installer_reply
    fi
}

fail() {
    printf "\nERROR: %s\n" "$1" >&2
    pause_on_exit
    exit 1
}

if [ ! -f "$SCRIPT_DIR/GoldAdvisorMidnight.toc" ]; then
    fail "Run this installer from inside the GoldAdvisorMidnight source folder."
fi

# Priority: a path passed to the command, then an environment override, then
# the standard macOS Retail installation path.
ADDONS_DIR="${1:-${GAM_WOW_ADDONS_DIR:-$DEFAULT_ADDONS_DIR}}"
ADDONS_DIR="${ADDONS_DIR%/}"

case "$ADDONS_DIR" in
    */Interface/AddOns)
        ;;
    *)
        fail "Destination must be a WoW Interface/AddOns folder: $ADDONS_DIR"
        ;;
esac

if [ ! -d "$ADDONS_DIR" ]; then
    fail "WoW AddOns folder was not found: $ADDONS_DIR"
fi

if ! command -v rsync >/dev/null 2>&1; then
    fail "rsync is required but was not found."
fi

TARGET_DIR="$ADDONS_DIR/$ADDON_NAME"
BACKUP_ROOT="$(dirname "$ADDONS_DIR")/AddOnBackups"

printf "Gold Advisor Midnight workspace installer\n"
printf "Source:      %s\n" "$SCRIPT_DIR"
printf "Destination: %s\n" "$TARGET_DIR"

if [ -d "$TARGET_DIR" ]; then
    TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
    BACKUP_DIR="$BACKUP_ROOT/$ADDON_NAME-$TIMESTAMP"
    mkdir -p "$BACKUP_DIR"
    rsync -a "$TARGET_DIR/" "$BACKUP_DIR/"
    printf "Backup:      %s\n" "$BACKUP_DIR"
fi

mkdir -p "$TARGET_DIR"
rsync -a --delete \
    --exclude '.DS_Store' \
    --exclude '.git/' \
    --exclude '.github/' \
    --exclude '.vscode/' \
    --exclude '.gitignore' \
    --exclude 'docs/' \
    --exclude 'tests/' \
    --exclude 'tools/' \
    --exclude '*.command' \
    "$SCRIPT_DIR/" "$TARGET_DIR/"

if [ ! -f "$TARGET_DIR/GoldAdvisorMidnight.toc" ]; then
    fail "Copy completed without the addon TOC file."
fi

VERSION="$(awk -F ': ' '/^## Version:/ { print $2; exit }' "$TARGET_DIR/GoldAdvisorMidnight.toc")"
printf "\nInstalled Gold Advisor Midnight %s successfully.\n" "${VERSION:-unknown-version}"
printf "If WoW is running, use /reload before testing.\n"

pause_on_exit
