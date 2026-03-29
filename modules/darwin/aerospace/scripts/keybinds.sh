#!/usr/bin/env bash

# AeroSpace keybind cheatsheet. Opens in a floating Ghostty window.
# Bound to: cmd-shift-i via AeroSpace

cat <<'EOF'
╔══════════════════════════════════════════════════════════════╗
║                   AeroSpace Keybinds                        ║
╠══════════════════════════════════════════════════════════════╣
║                                                              ║
║  WINDOW MANAGEMENT                                           ║
║  cmd-shift-q          Close window                           ║
║  cmd-shift-w          Toggle floating / tiling               ║
║  cmd-shift-enter      Toggle fullscreen                      ║
║                                                              ║
║  FOCUS (vim keys)                                            ║
║  cmd-shift-h/j/k/l   Focus left / down / up / right         ║
║                                                              ║
║  MOVE WINDOW                                                 ║
║  cmd-ctrl-shift-hjkl  Move left / down / up / right          ║
║  cmd-ctrl-shift-←/→   Move to prev / next workspace          ║
║                                                              ║
║  WORKSPACES                                                  ║
║  cmd-shift-1..0       Switch to workspace 1-10               ║
║  cmd-ctrl-shift-1..0  Move window to workspace 1-10          ║
║  cmd-shift-←/→        Prev / next workspace                  ║
║  cmd-shift-tab        Back and forth                         ║
║                                                              ║
║  LAYOUT                                                      ║
║  cmd-shift-/          Toggle tiles H/V                       ║
║  cmd-shift-,          Toggle accordion H/V                   ║
║  cmd-shift-r          Resize mode (hjkl, esc to exit)        ║
║                                                              ║
║  APP LAUNCHERS                                               ║
║  cmd-shift-space      App launcher (choose-gui)              ║
║  cmd-shift-t          Terminal (Ghostty)                     ║
║  cmd-shift-f          Browser (Firefox)                      ║
║  cmd-shift-e          File manager (Finder)                  ║
║  cmd-shift-m          Messaging (Beeper)                     ║
║  cmd-shift-d          System monitor (btop)                  ║
║  cmd-shift-u          Rebuild nix-darwin                     ║
║                                                              ║
║  FIREFOX PROFILES                                            ║
║  cmd-shift-z          Personal                               ║
║  cmd-shift-x          Social                                 ║
║  cmd-shift-c          Academic                               ║
║  cmd-shift-v          Sensitive                              ║
║                                                              ║
║  WORKSPACE MANAGEMENT                                        ║
║  cmd-shift-n          Consolidate (renumber 1, 2, 3...)      ║
║  cmd-shift-s          Swap two workspaces                    ║
║  cmd-shift-backspace  Reset workspace                        ║
║                                                              ║
║  PRODUCTIVITY                                                ║
║  cmd-shift-p          Project picker (choose → tmux)         ║
║  cmd-shift-a          Tmux session switcher (attach)         ║
║  cmd-shift-b          Claude session picker (browse/resume)  ║
║  cmd-shift-o          Quick scratchpad (nvim)                ║
║  cmd-shift-y          Publish notes to site                  ║
║                                                              ║
║  cmd-shift-i          This cheatsheet                        ║
║                                                              ║
╚══════════════════════════════════════════════════════════════╝
EOF

read -rsn1 -p "  Press any key to close..."
