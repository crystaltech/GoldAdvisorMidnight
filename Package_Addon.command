#!/bin/bash
# Package_Addon.command
# Creates a distributable zip of GoldAdvisorMidnight for beta testing.
# Output: GoldAdvisorMidnight-vX.X.X.zip in the project root.
# Double-click in Finder to run.

set -e
cd "$(dirname "$0")"

# ── Read version from TOC ──────────────────────────────────────────────────
VERSION=$(grep "^## Version:" GoldAdvisorMidnight/GoldAdvisorMidnight.toc \
          | awk '{print $NF}')

if [ -z "$VERSION" ]; then
    echo "ERROR: Could not read version from TOC."
    exit 1
fi

ZIPNAME="GoldAdvisorMidnight-v${VERSION}.zip"

echo "Packaging GoldAdvisorMidnight v${VERSION}..."

# ── Remove old package if it exists ───────────────────────────────────────
rm -f "$ZIPNAME"

# ── Create zip (addon folder only — no build/, references/, or dev files) ─
zip -r "$ZIPNAME" GoldAdvisorMidnight/ \
    -x "*.DS_Store" \
    -x "__MACOSX/*" \
    -x "*.swp" \
    -x "*~"

echo ""
echo "✓ Created: $(pwd)/$ZIPNAME"
echo ""
echo "Install instructions for beta testers:"
echo "  1. Extract $ZIPNAME"
echo "  2. Copy GoldAdvisorMidnight/ into:"
echo "       World of Warcraft/_retail_/Interface/AddOns/"
echo "  3. Launch WoW and /reload"
echo ""
