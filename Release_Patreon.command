#!/bin/bash
# Release_Patreon.command
# Builds a PROTECTED Patreon/members handoff zip.
# No git commit, no tag, no push — zip is for direct handoff to the client only.
#
# Usage: Double-click in Finder, or run from terminal.
#
# What it does:
#   1. Encodes Data/*Generated.lua → Data/*Encoded.lua
#   2. Patches the TOC to load *Encoded.lua instead of *Generated.lua
#   3. Builds a release zip → GoldAdvisorMidnight-vX.X.X-patreon.zip
#   4. Restores the TOC to dev state and removes temporary encoded files
#   5. Prints the output path — hand this zip to the client directly

set -euo pipefail
cd "$(dirname "$0")"

SRC_DIR="source/GoldAdvisorMidnight"
TOC="$SRC_DIR/GoldAdvisorMidnight.toc"
DATA_DIR="$SRC_DIR/Data"
OUT_DIR="releases"

# ── Cleanup: always restore TOC + remove encoded files ────────────────────
restore() {
    echo ""
    echo "Restoring TOC to dev state..."
    python3 - "$TOC" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    content = f.read()
content = content.replace("Data\\WorkbookEncoded.lua", "Data\\WorkbookGenerated.lua")
content = content.replace("Data\\StratsEncoded.lua",   "Data\\StratsGenerated.lua")
with open(path, "w", encoding="utf-8") as f:
    f.write(content)
print("  TOC restored.")
PYEOF
    rm -f "$DATA_DIR/StratsEncoded.lua" "$DATA_DIR/WorkbookEncoded.lua"
    echo "  Encoded files removed."
}

trap restore EXIT

# ── Read version ───────────────────────────────────────────────────────────
VERSION=$(grep "^## Version:" "$TOC" | awk '{print $NF}' | tr -d '\r')
if [ -z "$VERSION" ]; then
    echo "ERROR: Could not read version from TOC."
    exit 1
fi

ZIPNAME="GoldAdvisorMidnight-v${VERSION}-patreon.zip"
OUT_PATH="$OUT_DIR/$ZIPNAME"

echo "========================================================"
echo "  Gold Advisor Midnight — Patreon Handoff Build v${VERSION}"
echo "  (no git commit / tag / push)"
echo "========================================================"
echo ""

read -p "Build Patreon handoff zip v${VERSION}? [y/N] " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Aborted."
    exit 0
fi

# ── Step 1: Encode data files ─────────────────────────────────────────────
echo ""
echo "Encoding data files..."
python3 tools/encode_data.py
echo ""

# ── Step 2: Patch TOC ─────────────────────────────────────────────────────
echo "Patching TOC for protected build..."
python3 - "$TOC" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    content = f.read()
content = content.replace("Data\\WorkbookGenerated.lua", "Data\\WorkbookEncoded.lua")
content = content.replace("Data\\StratsGenerated.lua",   "Data\\StratsEncoded.lua")
with open(path, "w", encoding="utf-8") as f:
    f.write(content)
print("  TOC patched.")
PYEOF
echo ""

# ── Step 3: Build protected zip ───────────────────────────────────────────
echo "Building Patreon zip..."
mkdir -p "$OUT_DIR"
rm -f "$OUT_PATH"

(
    cd source
    zip -r "../$OUT_PATH" GoldAdvisorMidnight/ \
        -x "*.DS_Store" \
        -x "__MACOSX/*" \
        -x "*.swp" \
        -x "*~" \
        -x "GoldAdvisorMidnight/Data/StratsGenerated.lua" \
        -x "GoldAdvisorMidnight/Data/WorkbookGenerated.lua"
)

echo ""

# ── Step 4: Restore TOC + remove encoded files ────────────────────────────
trap - EXIT
restore

# ── Done ──────────────────────────────────────────────────────────────────
FULL_PATH="$(pwd)/$OUT_PATH"
echo ""
echo "========================================================"
echo "  Done! Patreon handoff zip ready."
echo ""
echo "  File: $FULL_PATH"
echo ""
echo "  Hand this zip to the client directly."
echo "  Do NOT commit or push — this is a handoff-only build."
echo "========================================================"
echo ""

# Open the releases folder in Finder for easy access
open "$(pwd)/$OUT_DIR"
