#!/usr/bin/env bash
# tmuxp session loader — picks a saved tmuxp config via fzf, loads it detached,
# then switches to it. Kills existing session first to get a clean reload.

config_dir="$HOME/.config/tmuxp"

session=$(ls "$config_dir"/*.yaml 2>/dev/null | xargs -n1 basename -s .yaml | fzf --prompt="Load session: ")
[ -z "$session" ] && exit 0

if tmux has-session -t "$session" 2>/dev/null; then
  tmux kill-session -t "$session"
fi

tmuxp load -d -y "$session" && tmux switch-client -t "$session"
