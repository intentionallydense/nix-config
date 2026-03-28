# Btop — cross-platform.
# Used by: modules/home/default.nix
{ ... }:
{
  home-manager.sharedModules = [
    (_: {
      programs.btop = {
        enable = true;
        settings = {
          color_theme = "catppuccin-mocha";
        };
      };
      xdg.configFile."btop/themes/catppuccin-mocha.theme".text = ''
        theme[main_bg]="#1E1E2E"
        theme[main_fg]="#CDD6F4"
        theme[title]="#CDD6F4"
        theme[hi_fg]="#89B4FA"
        theme[selected_bg]="#45475A"
        theme[selected_fg]="#89B4FA"
        theme[inactive_fg]="#7F849C"
        theme[graph_text]="#F5E0DC"
        theme[meter_bg]="#45475A"
        theme[proc_misc]="#F5E0DC"
        theme[cpu_box]="#cba6f7"
        theme[mem_box]="#a6e3a1"
        theme[net_box]="#eba0ac"
        theme[proc_box]="#89b4fa"
        theme[div_line]="#6C7086"
        theme[temp_start]="#a6e3a1"
        theme[temp_mid]="#f9e2af"
        theme[temp_end]="#f38ba8"
        theme[cpu_start]="#94e2d5"
        theme[cpu_mid]="#74c7ec"
        theme[cpu_end]="#b4befe"
        theme[free_start]="#cba6f7"
        theme[free_mid]="#b4befe"
        theme[free_end]="#89b4fa"
        theme[cached_start]="#74c7ec"
        theme[cached_mid]="#89b4fa"
        theme[cached_end]="#b4befe"
        theme[available_start]="#fab387"
        theme[available_mid]="#eba0ac"
        theme[available_end]="#f38ba8"
        theme[used_start]="#a6e3a1"
        theme[used_mid]="#94e2d5"
        theme[used_end]="#89dceb"
        theme[download_start]="#fab387"
        theme[download_mid]="#eba0ac"
        theme[download_end]="#f38ba8"
        theme[upload_start]="#a6e3a1"
        theme[upload_mid]="#94e2d5"
        theme[upload_end]="#89dceb"
        theme[process_start]="#74C7EC"
        theme[process_mid]="#89DCEB"
        theme[process_end]="#cba6f7"
      '';
    })
  ];
}
