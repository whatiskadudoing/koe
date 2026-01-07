#!/bin/bash
# Koe - Install with: curl -fsSL https://koe.sh/install | bash
set -e

REPO="whatiskadudoing/koe"
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

curl -fsSL "https://github.com/$REPO/releases/latest/download/koe-installer" -o "$TMP/koe-installer"
chmod +x "$TMP/koe-installer"
exec "$TMP/koe-installer"
