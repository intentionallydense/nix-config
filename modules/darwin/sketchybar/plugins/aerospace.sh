#!/usr/bin/env bash

# Highlight the active AeroSpace workspace, dim inactive ones.
# Called by SketchyBar on aerospace_workspace_change events.

ACTIVE_BG=0xffcba6f7    # Mauve
ACTIVE_TEXT=0xff1e1e2e   # Base (dark on mauve)
INACTIVE_TEXT=0xff6c7086 # Overlay0

if [ "$1" = "$FOCUSED_WORKSPACE" ]; then
  sketchybar --set "$NAME" \
    background.drawing=on \
    label.color="$ACTIVE_TEXT"
else
  sketchybar --set "$NAME" \
    background.drawing=off \
    label.color="$INACTIVE_TEXT"
fi
