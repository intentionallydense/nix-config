#!/usr/bin/env bash

# Tmux session switcher: lists active sessions via choose-gui, opens Ghostty
# attached to the selected one.
# Bound to: cmd-shift-s via AeroSpace

export PATH="/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin:/run/current-system/sw/bin:/etc/profiles/per-user/$USER/bin:$PATH"

# Exit if no tmux sessions exist
if ! tmux list-sessions &>/dev/null; then
  osascript -e 'display notification "No tmux sessions running" with title "Session Switcher"'
  exit 0
fi

selected=$(tmux list-sessions -F '#{session_name}: #{session_path} (#{session_windows} windows)' | choose)

[ -z "$selected" ] && exit 0

session_name=$(echo "$selected" | cut -d: -f1)

open -na Ghostty --args -e tmux attach-session -t "=$session_name"
