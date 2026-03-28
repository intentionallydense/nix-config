#!/usr/bin/env bash

# Claude Code session picker: lists recent sessions via choose-gui,
# then resume or summarize+launch in Ghostty.
# Bound to: cmd-shift-c via AeroSpace
# Follows the same pattern as project-picker.sh and session-switcher.sh.

export PATH="/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin:/run/current-system/sw/bin:/etc/profiles/per-user/$USER/bin:$HOME/.local/bin:$PATH"

selected=$(ccm list | choose)
[ -z "$selected" ] && exit 0

# Session ID is the last field (pipe-delimited)
session_id=$(echo "$selected" | awk -F' \\| ' '{print $NF}' | tr -d ' ')

action=$(printf "Resume session\nSummarize & start new" | choose -p "Action:")
[ -z "$action" ] && exit 0

# Launch in tmux (matches project-picker pattern).
# send-keys lets the command run inside an interactive shell so the
# session stays alive if the command exits, and PATH is inherited.
tmux_name="claude-${session_id:0:8}"

# Kill stale session with same name if it exists
tmux kill-session -t "=$tmux_name" 2>/dev/null

tmux new-session -d -s "$tmux_name"

case "$action" in
  Resume*)
    tmux send-keys -t "=$tmux_name" "claude --resume '$session_id'" Enter ;;
  Summarize*)
    tmux send-keys -t "=$tmux_name" "ccm summarize '$session_id' --launch" Enter ;;
esac

open -na Ghostty --args -e tmux attach-session -t "=$tmux_name"
