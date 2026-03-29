#!/usr/bin/env bash

# Reset workspace: close all windows on the focused workspace.
# The layout resets naturally once the workspace is empty.
# Bound to: cmd-shift-backspace via AeroSpace

export PATH="/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin:$PATH"

aerospace list-windows --workspace focused --format '%{window-id}' 2>/dev/null | while IFS= read -r wid; do
  [ -z "$wid" ] && continue
  aerospace close --window-id "$wid"
done
