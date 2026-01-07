#!/bin/bash
# Koe - Install with: curl -fsSL https://koe.sh/install | bash
set -e

REPO="whatiskadudoing/koe"
TMP=$(mktemp)
trap "rm -f $TMP" EXIT

curl -fsSL "https://github.com/$REPO/releases/latest/download/koe-installer" -o "$TMP"
chmod +x "$TMP"
"$TMP"
