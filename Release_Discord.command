#!/bin/bash
# Release_Discord.command
# Builds a Discord-member release zip and creates a GitHub PRE-RELEASE
# (not marked "latest" — does not affect the CurseForge-stable release).
#
# Usage: Double-click in Finder, or run from terminal.
#
# What it does:
#   1. Builds a release zip → GoldAdvisorMidnight-vX.X.X-discord.zip
#   2. Commits source changes, tags vX.X.X-discord, pushes, creates GitHub pre-release

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

# ── Step 1: Build zip ─────────────────────────────────────────────────────
echo ""
echo "Building Discord zip..."
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

echo ""
echo "  Created: $(pwd)/$OUT_PATH"
echo ""

# ── Step 2: Commit source changes ─────────────────────────────────────────
BRANCH=$(git rev-parse --abbrev-ref HEAD)
git add CHANGELOG.md
git add source/
git commit --allow-empty -m "release: $TAG (discord)"

# ── Step 3: Tag ───────────────────────────────────────────────────────────
git tag "$TAG"

# ── Step 4: Push ──────────────────────────────────────────────────────────
echo ""
echo "Pushing to GitHub..."
git push origin "$BRANCH"
git push origin "$TAG"

# ── Step 5: GitHub Pre-Release (NOT --latest) ─────────────────────────────
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
