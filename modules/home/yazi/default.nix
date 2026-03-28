# Yazi file manager — cross-platform.
# Used by: modules/home/default.nix
{ ... }:
{
  home-manager.sharedModules = [
    (_: {
      programs.yazi = {
        enable = true;
        shellWrapperName = "y";
        enableBashIntegration = true;
        enableZshIntegration = true;
        settings = {
          manager = {
            show_hidden = true;
            show_symlink = true;
            sort_dir_first = true;
            linemode = "size";
            ratio = [ 1 3 4 ];
          };
          preview = {
            tab_size = 4;
            image_filter = "triangle";
            max_width = 1920;
            max_height = 1080;
            image_quality = 90;
          };
        };
        keymap = {
          manager.prepend_keymap = [
            { on = [ "e" ]; run = "open"; }
            { on = [ "d" ]; run = "remove --force"; }
          ];
        };
        theme = {
          manager.border_symbol = " ";
          status = {
            separator_open = "";
            separator_close = "";
          };
        };
      };
    })
  ];
}
