#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="$ROOT/source/GoldAdvisorMidnight"
DEST="/Applications/World of Warcraft/_retail_/Interface/AddOns/GoldAdvisorMidnight"

echo "Syncing addon..."
rm -rf "$DEST"
cp -R "$SRC" "$DEST"

echo "Done."
