#!/bin/bash
# Package_Addon.command
# Creates a distributable zip of GoldAdvisorMidnight for beta testing.
# Source: source/GoldAdvisorMidnight/
# Output: releases/GoldAdvisorMidnight-vX.X.X.zip
# Double-click in Finder to run.

set -euo pipefail
cd "$(dirname "$0")"

SRC_DIR="source/GoldAdvisorMidnight"
OUT_DIR="releases"

# ── Read version from TOC ──────────────────────────────────────────────────
VERSION=$(grep "^## Version:" "$SRC_DIR/GoldAdvisorMidnight.toc" \
          | awk '{print $NF}' | tr -d '\r')

if [ -z "$VERSION" ]; then
    echo "ERROR: Could not read version from TOC."
    exit 1
fi

ZIPNAME="GoldAdvisorMidnight-v${VERSION}.zip"
OUT_PATH="$OUT_DIR/$ZIPNAME"

echo "Packaging GoldAdvisorMidnight v${VERSION}..."

# ── Remove old package if it exists ───────────────────────────────────────
mkdir -p "$OUT_DIR"
rm -f "$OUT_PATH"

# ── Create zip (addon folder only — no build/, references/, or dev files) ─
(
    cd source
    zip -r "../$OUT_PATH" GoldAdvisorMidnight/ \
    -x "*.DS_Store" \
    -x "__MACOSX/*" \
    -x "*.swp" \
    -x "*~"
)

echo ""
echo "✓ Created: $(pwd)/$OUT_PATH"
echo ""
echo "Install instructions for beta testers:"
echo "  1. Extract $ZIPNAME"
echo "  2. Copy GoldAdvisorMidnight/ into:"
echo "       World of Warcraft/_retail_/Interface/AddOns/"
echo "  3. Launch WoW and /reload"
echo ""
