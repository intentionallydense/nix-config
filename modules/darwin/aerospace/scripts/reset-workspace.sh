#!/usr/bin/env bash

# Purge ghost windows from AeroSpace's tree, then refresh tiling.
# Ghosts happen because macOS Sequoia's Accessibility API doesn't
# reliably notify AeroSpace when windows are created or destroyed.
# See: https://github.com/nikitabobko/AeroSpace/issues/1615
# Bound to: cmd-shift-backspace via AeroSpace

export PATH="/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin:$PATH"

# Get window IDs that AeroSpace thinks exist
aero_ids=$(aerospace list-windows --all --format '%{window-id}' 2>/dev/null)

# Get window IDs that macOS actually has (via CGWindowListCopyWindowInfo)
macos_ids=$(swift -e '
import CoreGraphics
let wins = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as! [[String: Any]]
for w in wins {
    if let id = w[kCGWindowNumber as String] as? Int { print(id) }
}
' 2>/dev/null)

# Close any AeroSpace window that macOS doesn't know about
for wid in $aero_ids; do
  if ! echo "$macos_ids" | grep -qx "$wid"; then
    aerospace close --window-id "$wid" 2>/dev/null
  fi
done

# Flatten workspace tree to fix layout after ghost removal
aerospace flatten-workspace-tree 2>/dev/null
