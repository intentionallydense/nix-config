#!/bin/bash

# Opens a macOS app and forces it to focus.
# open -na from AeroSpace's exec-and-forget doesn't reliably bring
# windows to the foreground; osascript activate fixes that.
# Usage: open-and-focus.sh AppName [extra open flags...]
# Full paths because AeroSpace exec-and-forget has a minimal PATH.

export PATH="/usr/bin:/usr/local/bin:/opt/homebrew/bin:$PATH"

app="$1"
shift
/usr/bin/open -na "$app" "$@"
/usr/bin/osascript -e "tell application \"$app\" to activate"
