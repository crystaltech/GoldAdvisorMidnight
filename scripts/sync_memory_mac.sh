#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./scripts/sync_memory_mac.sh [source_dir]
#
# Default source_dir:
#   GoldAdvisorMidnight/memory
#
# Files are copied into:
#   GoldAdvisorMidnight/memory/snapshots/mac

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="${1:-$REPO_ROOT/GoldAdvisorMidnight/memory}"
DEST_DIR="$REPO_ROOT/GoldAdvisorMidnight/memory/snapshots/mac"

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "Source directory does not exist: $SOURCE_DIR" >&2
  exit 1
fi

mkdir -p "$DEST_DIR"

# Copy markdown/txt/lua/json files recursively, excluding snapshot destinations.
rsync -a --prune-empty-dirs \
  --include='*/' \
  --include='*.md' \
  --include='*.txt' \
  --include='*.lua' \
  --include='*.json' \
  --exclude='snapshots/' \
  --exclude='*' \
  "$SOURCE_DIR/" "$DEST_DIR/"

echo "Memory sync complete (mac):"
echo "  Source: $SOURCE_DIR"
echo "  Dest:   $DEST_DIR"
