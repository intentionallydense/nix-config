#!/usr/bin/env bash

# Consolidate workspaces: renumber non-empty workspaces to 1, 2, 3...
# e.g. windows on 1, 4, 7 → moved to 1, 2, 3.
# Bound to: cmd-shift-n via AeroSpace

export PATH="/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin:$PATH"

target=1
for ws in $(seq 1 10); do
  wids=$(aerospace list-windows --workspace "$ws" --format '%{window-id}' 2>/dev/null)
  [ -z "$wids" ] && continue

  if [ "$ws" -ne "$target" ]; then
    while IFS= read -r wid; do
      [ -z "$wid" ] && continue
      aerospace focus --window-id "$wid"
      aerospace move-node-to-workspace "$target"
    done <<< "$wids"
  fi
  target=$((target + 1))
done

aerospace workspace 1
