#!/usr/bin/env bash

# App launcher using choose-gui. Scans /Applications and system apps,
# presents a fuzzy picker, and opens the selection.
# Bound to: cmd-shift-space via AeroSpace
# Full paths because AeroSpace exec-and-forget has a minimal PATH.

export PATH="/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin:$PATH"

selected=$(ls /Applications/ /Applications/Utilities/ /System/Applications/ /System/Applications/Utilities/ 2>/dev/null \
  | grep '\.app$' \
  | sed 's/\.app$//' \
  | sort -u \
  | choose)

[ -z "$selected" ] && exit 0

open -a "$selected"
# open -a doesn't always focus the window when called from a non-focused context
# (e.g. AeroSpace exec-and-forget). osascript forces macOS to bring it forward.
osascript -e "tell application \"$selected\" to activate"
