#!/usr/bin/env bash

# Publish Obsidian notes to Jekyll site with a single keypress.
# Shows output in Ghostty so you can see what was published.
# Bound to: cmd-shift-y via AeroSpace

export PATH="/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin:/run/current-system/sw/bin:/etc/profiles/per-user/$USER/bin:$PATH"

open -na Ghostty --args -e bash -c '
  echo "Publishing..."
  echo
  python3 ~/projects/active/intentionallydense/publish.py --go --push
  echo
  read -rsn1 -p "Press any key to close..."
'
