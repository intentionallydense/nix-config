#!/usr/bin/env bash

# Quick scratchpad: presents a choose-gui picker of existing notes in the
# Obsidian vault (magnesium/5. notes/), plus a "New" option for timestamped files.
# Bound to: cmd-shift-o via AeroSpace

export PATH="/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin:/run/current-system/sw/bin:/etc/profiles/per-user/$USER/bin:$PATH"

notes_dir="$HOME/Documents/obsidian/magnesium/5. notes"
mkdir -p "$notes_dir"

# Build the picker list: "New note" first, then existing files (newest first)
existing=$(ls -t "$notes_dir"/*.md 2>/dev/null | while read -r f; do basename "$f"; done)
choices=$(printf "+ New note\n%s" "$existing")

selected=$(echo "$choices" | choose)

[ -z "$selected" ] && exit 0

if [ "$selected" = "+ New note" ]; then
  selected="$(date '+%Y-%m-%d_%H%M').md"
fi

open -na Ghostty --args -e nvim "$notes_dir/$selected"
