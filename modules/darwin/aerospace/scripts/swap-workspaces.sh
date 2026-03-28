#!/usr/bin/env bash

# Swap two workspaces by moving all their windows.
# Uses choose-gui to pick source and destination.
# Bound to: cmd-shift-n via AeroSpace

export PATH="/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin:$PATH"

# Pick the two workspaces
ws_a=$(aerospace list-workspaces --all | choose -p "Move workspace:")
[ -z "$ws_a" ] && exit 0

ws_b=$(aerospace list-workspaces --all | choose -p "Next to workspace (swap):")
[ -z "$ws_b" ] && exit 0
[ "$ws_a" = "$ws_b" ] && exit 0

# Capture window IDs before moving anything
a_wids=$(aerospace list-windows --workspace "$ws_a" --format '%{window-id}' 2>/dev/null)
b_wids=$(aerospace list-windows --workspace "$ws_b" --format '%{window-id}' 2>/dev/null)

# Move A → B
while IFS= read -r wid; do
  [ -z "$wid" ] && continue
  aerospace focus --window-id "$wid"
  aerospace move-node-to-workspace "$ws_b"
done <<< "$a_wids"

# Move B (original) → A
while IFS= read -r wid; do
  [ -z "$wid" ] && continue
  aerospace focus --window-id "$wid"
  aerospace move-node-to-workspace "$ws_a"
done <<< "$b_wids"

aerospace workspace "$ws_b"
