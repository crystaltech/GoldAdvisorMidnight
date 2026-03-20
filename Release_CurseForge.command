#!/bin/bash
# Release_CurseForge.command
# Builds a PROTECTED CurseForge release zip, creates a stable GitHub release
# (marked --latest), and uploads the zip to CurseForge via the API.
#
# Usage: Double-click in Finder, or run from terminal.
#
# Prerequisites:
#   - Fill in .env with CF_API_TOKEN, CF_PROJECT_ID, CF_GAME_VERSION_ID
#   - You must be on the main branch (or merge discord → main first)
#   - Bump version in Constants.lua + TOC before running
#   - Add a changelog entry to CHANGELOG.md
#
# What it does:
#   1. Loads .env credentials
#   2. Encodes Data/*Generated.lua → Data/*Encoded.lua
#   3. Patches the TOC to load *Encoded.lua instead of *Generated.lua
#   4. Builds a release zip → GoldAdvisorMidnight-vX.X.X-protected.zip
#   5. Restores the TOC to dev state and removes temporary encoded files
#   6. Commits source changes, tags vX.X.X, pushes to main
#   7. Creates GitHub release (--latest)
#   8. Uploads zip to CurseForge via API

set -euo pipefail
cd "$(dirname "$0")"

SRC_DIR="source/GoldAdvisorMidnight"
TOC="$SRC_DIR/GoldAdvisorMidnight.toc"
DATA_DIR="$SRC_DIR/Data"
OUT_DIR="releases"

# ── Load .env credentials ──────────────────────────────────────────────────
if [ ! -f ".env" ]; then
    echo "ERROR: .env file not found. Create it with CF_API_TOKEN, CF_PROJECT_ID, CF_GAME_VERSION_ID."
    exit 1
fi
set -o allexport
source .env
set +o allexport

if [ -z "${CF_API_TOKEN:-}" ] || [ -z "${CF_PROJECT_ID:-}" ] || [ -z "${CF_GAME_VERSION_ID:-}" ]; then
    echo "ERROR: .env is missing one or more required values:"
    echo "  CF_API_TOKEN, CF_PROJECT_ID, CF_GAME_VERSION_ID"
    exit 1
fi

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

TAG="v${VERSION}"
ZIPNAME="GoldAdvisorMidnight-${TAG}-protected.zip"
OUT_PATH="$OUT_DIR/$ZIPNAME"

echo "========================================================"
echo "  Gold Advisor Midnight — CurseForge Release $TAG"
echo "  (GitHub stable release + CurseForge upload)"
echo "========================================================"
echo ""

# ── Confirm on main branch ────────────────────────────────────────────────
BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [ "$BRANCH" != "main" ]; then
    echo "WARNING: You are on branch '$BRANCH', not 'main'."
    read -p "Continue anyway? [y/N] " branch_confirm
    if [[ "$branch_confirm" != "y" && "$branch_confirm" != "Y" ]]; then
        echo "Aborted. Merge to main first."
        exit 0
    fi
fi

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

read -p "Build CurseForge release $TAG? [y/N] " confirm
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
echo "Building CurseForge zip..."
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
git add CHANGELOG.md
git add source/
git commit --allow-empty -m "release: $TAG (curseforge)"

# ── Step 6: Tag ───────────────────────────────────────────────────────────
git tag "$TAG"

# ── Step 7: Push ──────────────────────────────────────────────────────────
echo ""
echo "Pushing to GitHub..."
git push origin main
git push origin "$TAG"

# ── Step 8: GitHub Stable Release (--latest) ──────────────────────────────
echo ""
echo "Creating GitHub stable release $TAG..."
gh release create "$TAG" "$OUT_PATH" \
    --title "$TAG" \
    --latest \
    --generate-notes

# ── Step 9: Upload to CurseForge ──────────────────────────────────────────
echo ""
echo "Uploading to CurseForge..."

# Extract top changelog section for patch notes
CHANGELOG_TEXT=$(python3 - CHANGELOG.md "$VERSION" <<'PYEOF'
import sys, re
path, version = sys.argv[1], sys.argv[2]
with open(path, "r", encoding="utf-8") as f:
    content = f.read()
# Find the section for this version
pattern = rf"## \[{re.escape(version)}\].*?(?=\n## \[|\Z)"
match = re.search(pattern, content, re.DOTALL)
if match:
    print(match.group(0).strip())
else:
    print(f"v{version} release")
PYEOF
)

CF_METADATA=$(python3 -c "
import json, sys
meta = {
    'changelog': sys.argv[1],
    'changelogType': 'markdown',
    'gameVersions': [int(sys.argv[2])],
    'releaseType': 'release'
}
print(json.dumps(meta))
" "$CHANGELOG_TEXT" "$CF_GAME_VERSION_ID")

HTTP_STATUS=$(curl -s -o /tmp/cf_upload_response.json -w "%{http_code}" \
    -X POST \
    -H "X-Api-Token: $CF_API_TOKEN" \
    -F "metadata=$CF_METADATA" \
    -F "file=@$OUT_PATH" \
    "https://wow.curseforge.com/api/projects/$CF_PROJECT_ID/upload-file")

if [ "$HTTP_STATUS" = "200" ]; then
    FILE_ID=$(python3 -c "import json; d=json.load(open('/tmp/cf_upload_response.json')); print(d.get('id','unknown'))")
    echo "  CurseForge upload successful! File ID: $FILE_ID"
    echo "  View at: https://www.curseforge.com/wow/addons/gold-advisor-midnight/files/$FILE_ID"
else
    echo "  ERROR: CurseForge upload failed (HTTP $HTTP_STATUS)"
    cat /tmp/cf_upload_response.json
    echo ""
    echo "  The GitHub release was already created. Upload the zip manually:"
    echo "  https://www.curseforge.com/wow/addons/gold-advisor-midnight/upload-file"
    exit 1
fi

# ── Done ──────────────────────────────────────────────────────────────────
echo ""
echo "========================================================"
echo "  Done! $TAG CurseForge release complete."
echo "  Zip:    $OUT_PATH"
echo "  GitHub: stable (latest)"
echo "  CF:     live"
echo "========================================================"
echo ""
