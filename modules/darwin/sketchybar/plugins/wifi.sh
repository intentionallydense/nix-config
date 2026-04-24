#!/usr/bin/env bash

# Wifi indicator — shows SSID when connected, icon dims when disconnected.
# Catppuccin Mocha palette.

TEXT=0xffcdd6f4      # Text
SUBTLE=0xff6c7086    # Overlay0

SSID=$(/System/Library/PrivateFrameworks/Apple80211.framework/Resources/airport -I 2>/dev/null | awk -F': ' '/^ *SSID/{print $2}')

if [ -n "$SSID" ]; then
  sketchybar --set "$NAME" \
    icon="󰤨" \
    icon.color="$TEXT" \
    label="$SSID"
else
  sketchybar --set "$NAME" \
    icon="󰤭" \
    icon.color="$SUBTLE" \
    label=""
fi
