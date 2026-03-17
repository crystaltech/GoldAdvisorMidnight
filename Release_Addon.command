#!/bin/bash
# Release_Addon.command
# One-step release: reads version from TOC, builds zip, commits all staged/modified
# source files, tags, and pushes to GitHub.
#
# Usage:
#   1. Make your code changes.
#   2. Bump ADDON_VERSION in Constants.lua and ## Version: in the TOC.
#   3. Add a CHANGELOG.md entry for the new version.
#   4. Double-click this script (or run from terminal).
#
# The script will:
#   - Confirm the version and show a git diff summary before doing anything
#   - Build the release zip
#   - Commit all modified tracked files in source/ + CHANGELOG.md
#   - Tag vX.X.X
#   - Push commits and tag to origin/main
#   - Print the GitHub releases URL so you can attach the zip

set -euo pipefail
cd "$(dirname "$0")"

SRC_DIR="source/GoldAdvisorMidnight"

# ── Read version ───────────────────────────────────────────────────────────
VERSION=$(grep "^## Version:" "$SRC_DIR/GoldAdvisorMidnight.toc" \
          | awk '{print $NF}' | tr -d '\r')

if [ -z "$VERSION" ]; then
    echo "ERROR: Could not read version from TOC."
    exit 1
fi

TAG="v${VERSION}"

echo "========================================"
echo "  Gold Advisor Midnight — Release $TAG"
echo "========================================"
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

read -p "Release $TAG? [y/N] " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Aborted."
    exit 0
fi

# ── Build zip ─────────────────────────────────────────────────────────────
bash Package_Addon.command
echo ""

# ── Commit ────────────────────────────────────────────────────────────────
git add CHANGELOG.md
git add source/
git commit -m "release: $TAG"

# ── Tag ───────────────────────────────────────────────────────────────────
git tag "$TAG"

# ── Push ──────────────────────────────────────────────────────────────────
echo ""
echo "Pushing to GitHub..."
git push origin main
git push origin "$TAG"

# ── GitHub Release ─────────────────────────────────────────────────────────
ZIPFILE="releases/GoldAdvisorMidnight-${TAG}.zip"
echo ""
echo "Creating GitHub release $TAG..."
gh release create "$TAG" "$ZIPFILE" \
    --title "$TAG" \
    --latest \
    --generate-notes

# ── Done ──────────────────────────────────────────────────────────────────
echo ""
echo "========================================"
echo "  Done! $TAG released."
echo "  Zip: $ZIPFILE"
echo "========================================"
echo ""
