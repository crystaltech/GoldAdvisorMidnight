#!/bin/bash
# Release_Patreon.command
# Builds a plain handoff zip for direct distribution.
# No git commit, no tag, no push — zip is for direct handoff to the client only.
#
# Usage: Double-click in Finder, or run from terminal.
#
# What it does:
#   1. Builds a release zip → GoldAdvisorMidnight-vX.X.X-patreon.zip
#   2. Opens the releases folder in Finder for easy access

set -euo pipefail
cd "$(dirname "$0")"

SRC_DIR="source/GoldAdvisorMidnight"
TOC="$SRC_DIR/GoldAdvisorMidnight.toc"
OUT_DIR="releases"

# ── Read version ───────────────────────────────────────────────────────────
VERSION=$(grep "^## Version:" "$TOC" | awk '{print $NF}' | tr -d '\r')
if [ -z "$VERSION" ]; then
    echo "ERROR: Could not read version from TOC."
    exit 1
fi

ZIPNAME="GoldAdvisorMidnight-v${VERSION}-patreon.zip"
OUT_PATH="$OUT_DIR/$ZIPNAME"

echo "========================================================"
echo "  Gold Advisor Midnight — Handoff Build v${VERSION}"
echo "  (no git commit / tag / push)"
echo "========================================================"
echo ""

read -p "Build handoff zip v${VERSION}? [y/N] " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Aborted."
    exit 0
fi

# ── Build zip ─────────────────────────────────────────────────────────────
echo ""
echo "Building zip..."
mkdir -p "$OUT_DIR"
rm -f "$OUT_PATH"

(
    cd source
    zip -r "../$OUT_PATH" GoldAdvisorMidnight/ \
        -x "*.DS_Store" \
        -x "__MACOSX/*" \
        -x "*.swp" \
        -x "*~"
)

# ── Done ──────────────────────────────────────────────────────────────────
FULL_PATH="$(pwd)/$OUT_PATH"
echo ""
echo "========================================================"
echo "  Done! Handoff zip ready."
echo ""
echo "  File: $FULL_PATH"
echo ""
echo "  Hand this zip to the client directly."
echo "  Do NOT commit or push — this is a handoff-only build."
echo "========================================================"
echo ""

# Open the releases folder in Finder for easy access
open "$(pwd)/$OUT_DIR"
