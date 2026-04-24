#!/usr/bin/env bash

# Battery indicator — percentage + nerd font icon, color shifts when low.
# Catppuccin Mocha palette.

GREEN=0xffa6e3a1    # Green
YELLOW=0xfff9e2af   # Yellow
RED=0xfff38ba8      # Red
TEXT=0xffcdd6f4     # Text

BATT_INFO=$(pmset -g batt)
PERCENT=$(echo "$BATT_INFO" | grep -Eo '[0-9]+%' | head -1 | tr -d '%')
CHARGING=$(echo "$BATT_INFO" | grep -q "AC Power" && echo 1 || echo 0)

if [ -z "$PERCENT" ]; then
  sketchybar --set "$NAME" drawing=off
  exit 0
fi

# Icon selection
if [ "$CHARGING" -eq 1 ]; then
  ICON="󰂄"
  COLOR="$GREEN"
elif [ "$PERCENT" -ge 80 ]; then
  ICON="󰁹"
  COLOR="$TEXT"
elif [ "$PERCENT" -ge 60 ]; then
  ICON="󰁿"
  COLOR="$TEXT"
elif [ "$PERCENT" -ge 40 ]; then
  ICON="󰁽"
  COLOR="$TEXT"
elif [ "$PERCENT" -ge 20 ]; then
  ICON="󰁻"
  COLOR="$YELLOW"
else
  ICON="󰂃"
  COLOR="$RED"
fi

sketchybar --set "$NAME" \
  drawing=on \
  icon="$ICON" \
  icon.color="$COLOR" \
  label="${PERCENT}%"
