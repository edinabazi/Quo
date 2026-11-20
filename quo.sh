#!/bin/bash
# Quo: this fork of Search, built under its own name and bundle id, so it
# keeps its own data, settings and WebKit storage beside an installed Search.
#
#   ./quo.sh              build build/Quo.app
#   ./quo.sh install      build it and put it in /Applications (quits Quo first)
#
# Data lives in ~/Library/Application Support/Quo, the defaults under
# com.edinabazi.quo, cookies and site data in WebKit's container for that id.
# Saved passwords are shared with Search through the keychain: each one asks
# for the login password once, since the two are signed by different people.
set -euo pipefail
cd "$(dirname "$0")"
# Its icon: Icon/Quo.icon, made in Icon Composer, with its Dark, Clear and
# Tinted styles. On a Mac without Icon Composer, the older mark instead: a
# soft tile with a Q cut out (Icon/quo-mark.svg), drawn by Icon/icon.swift.
# iCloud sync, once Quo.provisionprofile (git-ignored) is beside this script:
# a Developer ID profile for com.edinabazi.quo with the iCloud container
# iCloud.com.edinabazi.quo and push. Without it, Quo builds as before, with
# folder sync only.
if [ -f Quo.provisionprofile ]; then
  export SEARCH_PROFILE=Quo.provisionprofile SEARCH_ENTITLEMENTS=Quo.entitlements
fi
SEARCH_NAME=Quo SEARCH_BUNDLE_ID=com.edinabazi.quo SEARCH_ICON=Icon/Quo.icon \
  SEARCH_FEEDBACK=https://github.com/edinabazi/Quo/issues/new \
  SEARCH_MARK=Icon/quo-mark.svg SEARCH_MARK_FRACTION=0.56 ./build.sh release app
if [ "${1:-}" = "install" ]; then
  osascript -e 'tell application id "com.edinabazi.quo" to quit' 2>/dev/null || true
  sleep 1
  rm -rf /Applications/Quo.app
  cp -R build/Quo.app /Applications/Quo.app
  echo "installed: /Applications/Quo.app"
fi
