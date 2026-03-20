#!/bin/bash
# Release_Discord.command
# Builds a PROTECTED Discord-member release zip and creates a GitHub PRE-RELEASE
# (not marked "latest" — does not affect the CurseForge-stable release).
#
# Usage: Double-click in Finder, or run from terminal.
#
# What it does:
#   1. Encodes Data/*Generated.lua → Data/*Encoded.lua
#   2. Patches the TOC to load *Encoded.lua instead of *Generated.lua
#   3. Builds a release zip → GoldAdvisorMidnight-vX.X.X-discord.zip
#   4. Restores the TOC to dev state and removes temporary encoded files
#   5. Commits source changes, tags vX.X.X-discord, pushes, creates GitHub pre-release
#
# The git repo always stays in dev state. Protected zip is the only encoded artifact.
# GitHub pre-release is NOT marked latest — CurseForge users see only stable releases.

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

TAG="v${VERSION}-discord"
ZIPNAME="GoldAdvisorMidnight-v${VERSION}-discord.zip"
OUT_PATH="$OUT_DIR/$ZIPNAME"

echo "========================================================"
echo "  Gold Advisor Midnight — Discord Release $TAG"
echo "  (GitHub pre-release — NOT marked latest)"
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

read -p "Build Discord release $TAG? [y/N] " confirm
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
echo "Building Discord zip..."
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
trap - EXIT
restore

# ── Step 5: Commit source changes ─────────────────────────────────────────
echo ""
BRANCH=$(git rev-parse --abbrev-ref HEAD)
git add CHANGELOG.md
git add source/
git commit --allow-empty -m "release: $TAG (discord)"

# ── Step 6: Tag ───────────────────────────────────────────────────────────
git tag "$TAG"

# ── Step 7: Push ──────────────────────────────────────────────────────────
echo ""
echo "Pushing to GitHub..."
git push origin "$BRANCH"
git push origin "$TAG"

# ── Step 8: GitHub Pre-Release (NOT --latest) ─────────────────────────────
echo ""
echo "Creating GitHub pre-release $TAG..."
gh release create "$TAG" "$OUT_PATH" \
    --title "Discord Early Access $TAG" \
    --prerelease \
    --generate-notes

# ── Done ──────────────────────────────────────────────────────────────────
echo ""
echo "========================================================"
echo "  Done! $TAG Discord release complete."
echo "  Zip: $OUT_PATH"
echo "  GitHub: pre-release (not marked latest)"
echo "========================================================"
echo ""
