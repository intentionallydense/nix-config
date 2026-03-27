#!/usr/bin/env bash
# Smart clipboard: pick from history, then auto-paste into the focused window.
# Uses Ctrl+Shift+V for terminals, Ctrl+V for everything else.

result=$(cliphist list | rofi -dmenu \
  -kb-custom-1 "Control-Delete" \
  -kb-custom-2 "Alt-Delete" \
  -theme "$HOME/.config/rofi/launchers/type-1/style-6.rasi")

case "$?" in
  0)
    [ -z "$result" ] && exit
    cliphist decode <<<"$result" | wl-copy
    # Check if the focused window is a terminal
    activeclass=$(hyprctl activewindow -j | jq -r '.class // ""')
    case "$activeclass" in
      *kitty*|*Alacritty*|*foot*|*wezterm*|*konsole*|*xterm*|*terminal*|*Terminal*)
        wtype -M ctrl -M shift -k v
        ;;
      *)
        wtype -M ctrl -k v
        ;;
    esac
    ;;
  10)
    cliphist delete <<<"$result"
    ;;
  11)
    cliphist wipe
    ;;
esac
