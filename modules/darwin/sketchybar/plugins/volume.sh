#!/usr/bin/env bash

# Volume indicator — nerd font icon changes with level.
# Catppuccin Mocha palette.

TEXT=0xffcdd6f4      # Text
SUBTLE=0xff6c7086    # Overlay0

VOL=$(osascript -e "output volume of (get volume settings)" 2>/dev/null)
MUTED=$(osascript -e "output muted of (get volume settings)" 2>/dev/null)

if [ "$MUTED" = "true" ] || [ "$VOL" -eq 0 ] 2>/dev/null; then
  ICON="󰖁"
  COLOR="$SUBTLE"
  LABEL=""
elif [ "$VOL" -le 30 ]; then
  ICON="󰕿"
  COLOR="$TEXT"
  LABEL="${VOL}%"
elif [ "$VOL" -le 70 ]; then
  ICON="󰖀"
  COLOR="$TEXT"
  LABEL="${VOL}%"
else
  ICON="󰕾"
  COLOR="$TEXT"
  LABEL="${VOL}%"
fi

sketchybar --set "$NAME" \
  icon="$ICON" \
  icon.color="$COLOR" \
  label="$LABEL"
