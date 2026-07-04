# Karabiner-Elements — darwin only.
# Caps Lock → Escape (tap) / Hyper key (hold).
# Used by: hosts/silicon/default.nix, hosts/germanium/configuration.nix
{ lib, ... }:
{
  home-manager.sharedModules = [
    ({ lib, ... }: {
      # Karabiner manages its own config file and will overwrite a symlink,
      # so we use force to ensure our declarative version wins on each rebuild.
      # The activation script kills the GUI that pops up on config change —
      # the background daemon (karabiner_grabber/observer) keeps running.
      home.activation.killKarabinerGUI = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        /usr/bin/killall "Karabiner-Elements" 2>/dev/null || true
      '';
      home.file.".config/karabiner/karabiner.json" = {
        force = true;
        text = builtins.toJSON {
          global = {
            ask_for_confirmation_before_quitting = false;
            check_for_updates_on_startup = false;
            show_in_menu_bar = false;
            show_profile_name_in_menu_bar = false;
            unsafe_ui = false;
          };
          profiles = [
            {
              name = "Default";
              selected = true;
              complex_modifications = {
                parameters = {
                  "basic.simultaneous_threshold_milliseconds" = 50;
                  "basic.to_delayed_action_delay_milliseconds" = 500;
                  "basic.to_if_alone_timeout_milliseconds" = 200;
                  "basic.to_if_held_down_threshold_milliseconds" = 500;
                };
                rules = [
                  {
                    description = "Caps Lock → Escape (tap) / Hyper (hold)";
                    manipulators = [
                      {
                        type = "basic";
                        from = {
                          key_code = "caps_lock";
                          modifiers.optional = [ "any" ];
                        };
                        to = [
                          {
                            # Hyper = Cmd+Ctrl+Opt+Shift
                            key_code = "left_shift";
                            modifiers = [
                              "left_command"
                              "left_control"
                              "left_option"
                            ];
                          }
                        ];
                        to_if_alone = [
                          { key_code = "escape"; }
                        ];
                      }
                    ];
                  }
                  {
                    # Sneak/shift-click on an easy pinky key for MCSR. 1:1 remap
                    # (legal for ranked). Scoped to the game's java process only:
                    # Prism-managed runtimes live under PrismLauncher/java/, the
                    # Homebrew JDK matches openjdk@21. NB: in-game `grave` binds
                    # (currently playerlist) become unreachable while this is active.
                    description = "Backtick → Shift while Minecraft is frontmost";
                    manipulators = [
                      {
                        type = "basic";
                        from = {
                          key_code = "grave_accent_and_tilde";
                          modifiers.optional = [ "any" ];
                        };
                        to = [
                          { key_code = "left_shift"; }
                        ];
                        conditions = [
                          {
                            type = "frontmost_application_if";
                            file_paths = [
                              "PrismLauncher/java/.*/bin/java"
                              "openjdk@21/.*/bin/java"
                            ];
                          }
                        ];
                      }
                    ];
                  }
                ];
              };
              devices = [ ];
              fn_function_keys = [ ];
              parameters = {
                delay_milliseconds_before_open_device = 1000;
              };
              simple_modifications = [ ];
              virtual_hid_keyboard = {
                country_code = 0;
                # Declaring the type explicitly is what stops the macOS Keyboard Setup
                # Assistant from popping up on every rebuild: without it, the force-deployed
                # virtual keyboard has no declared type, so macOS keeps asking us to identify
                # it (and reverts any GUI choice). On this British ISO Apple keyboard, "ansi"
                # is (counterintuitively) what makes the §/± top-left key emit keycode 10 (§);
                # "iso" makes it emit keycode 50 (backtick). Keep "ansi" — the AeroSpace
                # screenshot binding (cmd-shift-sectionSign) keys off the § keycode.
                keyboard_type_v2 = "ansi";
                indicate_sticky_modifier_keys_state = true;
                mouse_key_xy_scale = 1.0;
              };
            }
          ];
        };
      };
    })
  ];
}
