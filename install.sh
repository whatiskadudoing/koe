#!/bin/bash
# Koe - Install with: bash <(curl -fsSL https://raw.githubusercontent.com/whatiskadudoing/koe/main/install.sh)
set -e

REPO="whatiskadudoing/koe"
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

echo "Downloading Koe installer..."
curl -fsSL "https://github.com/$REPO/releases/latest/download/koe-installer" -o "$TMP/koe-installer"
chmod +x "$TMP/koe-installer"

# Close stdin and reconnect to terminal before running interactive installer
exec < /dev/tty
"$TMP/koe-installer"
