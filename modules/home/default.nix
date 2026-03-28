# Shared home-manager modules, importable from both NixOS and nix-darwin hosts.
# Each sub-module uses the `home-manager.sharedModules` pattern so it works
# regardless of whether the host is NixOS or nix-darwin.
# Shared home-manager modules, importable from both NixOS and nix-darwin hosts.
# Each sub-module uses the `home-manager.sharedModules` pattern so it works
# regardless of whether the host is NixOS or nix-darwin.
{
  imports = [
    ./cli
    ./fish
    ./git
    ./ghostty
    ./starship
    ./tmux
    ./direnv
    ./lazygit
    ./btop
    ./yazi
    ./cava
  ];
}
