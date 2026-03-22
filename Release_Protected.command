#!/bin/bash
# Release_Protected.command
# Builds a PROTECTED release zip — data files are encoded, plain source files
# are excluded from the zip. Then commits, tags, and pushes to GitHub.
#
# Usage: Double-click in Finder, or run from terminal.
#
# What it does:
#   1. Encodes Data/*Generated.lua → Data/*Encoded.lua (via tools/encode_data.py)
#   2. Patches the TOC to load *Encoded.lua instead of *Generated.lua
#   3. Builds a release zip (plain *Generated.lua excluded from the zip)
#   4. Restores the TOC to dev state and removes the temporary encoded files
#   5. Commits all source changes, tags vX.X.X, pushes, creates GitHub release
#
# The git repo always stays in dev state (plain files, plain TOC).
# The protected zip is the only artifact that contains encoded data.

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
import sys, re
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

TAG="v${VERSION}"
ZIPNAME="GoldAdvisorMidnight-${TAG}-protected.zip"
OUT_PATH="$OUT_DIR/$ZIPNAME"

echo "========================================================"
echo "  Gold Advisor Midnight — Protected Release $TAG"
echo "========================================================"
echo ""

# ── Confirm tag doesn't already exist ─────────────────────────────────────
if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "ERROR: Tag $TAG already exists. Bump the version first."
    exit 1
fi

# ── Show what will be committed ───────────────────────────────────────────
echo "Changed files:"
git diff --name-only
git diff --cached --name-only
echo ""

read -p "Build protected release $TAG? [y/N] " confirm
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
echo "Building protected zip..."
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
echo "  Created: $(pwd)/$OUT_PATH"
echo ""

# ── Step 4: Restore TOC + remove encoded files ────────────────────────────
# Done via the trap, but we call it explicitly here so the git commit below
# uses the clean dev-state TOC (not the patched one).
trap - EXIT   # disable auto-trap; we're handling it manually
restore

# ── Step 5: Commit source changes ─────────────────────────────────────────
echo ""
git add CHANGELOG.md
git add source/
git commit -m "release: $TAG (protected)"

# ── Step 6: Tag ───────────────────────────────────────────────────────────
git tag "$TAG"

# ── Step 7: Push ──────────────────────────────────────────────────────────
echo ""
echo "Pushing to GitHub..."
git push origin main
git push origin "$TAG"

# ── Step 8: GitHub Release ─────────────────────────────────────────────────
echo ""
echo "Creating GitHub release $TAG..."
gh release create "$TAG" "$OUT_PATH" \
    --title "$TAG" \
    --latest \
    --generate-notes

# ── Done ──────────────────────────────────────────────────────────────────
echo ""
echo "========================================================"
echo "  Done! $TAG protected release complete."
echo "  Zip: $OUT_PATH"
echo "========================================================"
echo ""
