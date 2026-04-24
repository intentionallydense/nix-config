#!/usr/bin/env bash

# Update the front-app item when the focused application changes.
# Uses sketchybar's built-in app icon rendering.

if [ "$SENDER" = "front_app_switched" ]; then
  sketchybar --set "$NAME" label="$INFO" icon.background.image="app.$INFO"
fi
