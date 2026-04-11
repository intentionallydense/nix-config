# Aerospace tiling window manager — darwin only.
# Deploys aerospace.toml to ~/.config/aerospace/ via home-manager.
# Used by: hosts/silicon/default.nix, hosts/germanium/configuration.nix
{ vaultName, ... }:
{
  home-manager.sharedModules = [
    ({ lib, ... }: {
      home.activation.reloadAerospace = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
        aerospace reload-config 2>/dev/null || true
      '';
      home.file.".config/aerospace/aerospace.toml".source = ./aerospace.toml;
      home.file.".config/aerospace/scripts/app-launcher.sh" = {
        source = ./scripts/app-launcher.sh;
        executable = true;
      };
      home.file.".config/aerospace/scripts/keybinds.sh" = {
        source = ./scripts/keybinds.sh;
        executable = true;
      };
      home.file.".config/aerospace/scripts/consolidate-workspaces.sh" = {
        source = ./scripts/consolidate-workspaces.sh;
        executable = true;
      };
      home.file.".config/aerospace/scripts/swap-workspaces.sh" = {
        source = ./scripts/swap-workspaces.sh;
        executable = true;
      };
      home.file.".config/aerospace/scripts/project-picker.sh" = {
        source = ./scripts/project-picker.sh;
        executable = true;
      };
      home.file.".config/aerospace/scripts/session-switcher.sh" = {
        source = ./scripts/session-switcher.sh;
        executable = true;
      };
      home.file.".config/aerospace/scripts/claude-session-picker.sh" = {
        source = ./scripts/claude-session-picker.sh;
        executable = true;
      };
      home.file.".config/aerospace/scripts/scratchpad.sh" = {
        executable = true;
        text = ''
          #!/usr/bin/env bash

          # Quick scratchpad: presents a choose-gui picker of existing notes in the
          # Obsidian vault (${vaultName}/5. notes/), plus a "New" option for timestamped files.
          # Bound to: cmd-shift-o via AeroSpace

          export PATH="/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin:/run/current-system/sw/bin:/etc/profiles/per-user/$USER/bin:$PATH"

          notes_dir="$HOME/Documents/Obsidian/${vaultName}/5. notes"
          mkdir -p "$notes_dir"

          # Build the picker list: "New note" first, then existing files (newest first)
          existing=$(ls -t "$notes_dir"/*.md 2>/dev/null | while read -r f; do basename "$f"; done)
          choices=$(printf "+ New note\n%s" "$existing")

          selected=$(echo "$choices" | choose)

          [ -z "$selected" ] && exit 0

          if [ "$selected" = "+ New note" ]; then
            selected="$(date '+%Y-%m-%d_%H%M').md"
          fi

          open -na Ghostty --args -e nvim "$notes_dir/$selected"
        '';
      };
      home.file.".config/aerospace/scripts/reset-workspace.sh" = {
        source = ./scripts/reset-workspace.sh;
        executable = true;
      };
    })
  ];
}
