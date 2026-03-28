#!/usr/bin/env bash

# Project picker: scans ~/projects/ for project dirs (2 levels deep),
# presents a fuzzy picker via choose-gui, and opens Ghostty with a tmux
# session at that path. Reattaches if a session already exists.
# Bound to: cmd-shift-p via AeroSpace

export PATH="/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin:/run/current-system/sw/bin:/etc/profiles/per-user/$USER/bin:$PATH"

selected=$(find "$HOME/projects" -mindepth 2 -maxdepth 2 -type d 2>/dev/null | sort | choose)

[ -z "$selected" ] && exit 0

# Session name: sanitize directory basename (tmux disallows dots/colons)
session_name=$(basename "$selected" | tr '.:' '__')

if tmux has-session -t "=$session_name" 2>/dev/null; then
  open -na Ghostty --args -e tmux attach-session -t "=$session_name"
else
  tmux new-session -d -s "$session_name" -c "$selected"
  open -na Ghostty --args -e tmux attach-session -t "=$session_name"
fi
