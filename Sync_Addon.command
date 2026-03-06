#!/bin/bash

SRC="/Users/terry.pike/Desktop/GoldAdvisorAddon/GoldAdvisorMidnight"
DEST="/Applications/World of Warcraft/_retail_/Interface/AddOns/GoldAdvisorMidnight"

echo "Syncing addon..."
rm -rf "$DEST"
cp -R "$SRC" "$DEST"

echo "Done."