# Faithful port of germanium's four Mullvad-isolated Firefox profiles, declaratively.
# Each profile routes through its dedicated wireproxy SOCKS5 backend (see modules/programs/wireproxy):
#   Personal → PAC :1081 (Gothenburg) · Sensitive → SOCKS5 :1082 (Zurich)
#   Academic → PAC :1083 (Amsterdam)  · Social    → SOCKS5 :1084 (Ashburn)
# Personal/Academic use PAC files (Tailscale/local stays direct); Sensitive/Social go straight SOCKS5.
# Extensions come per-profile from NUR's rycee firefox-addons (pulled in directly — the repo's
# overlay isn't wired into pkgs). Merges alongside the shared firefox module's `default` profile.
# Used by: hosts/silicon/nixos.nix
{
  inputs,
  pkgs,
  ...
}:
let
  firefox-addons = inputs.nur.legacyPackages.${pkgs.stdenv.hostPlatform.system}.repos.rycee.firefox-addons;
in
{
  home-manager.sharedModules = [
    (
      { config, ... }:
      let
        pacUrl = name: "file://${config.home.homeDirectory}/.config/firefox-pac/${name}.pac";
        # SOCKS5-only proxy prefs (Sensitive, Social).
        socksProxy = port: {
          "network.proxy.type" = 1;
          "network.proxy.socks" = "127.0.0.1";
          "network.proxy.socks_port" = port;
          "network.proxy.socks_remote_dns" = true;
        };
      in
      {
        programs.firefox.profiles = {
          Personal = {
            id = 1;
            settings = {
              "network.proxy.type" = 2;
              "network.proxy.autoconfig_url" = pacUrl "personal";
              "network.proxy.socks_remote_dns" = true;
            };
            extensions.packages = with firefox-addons; [
              ublock-origin
              multi-account-containers
              cookie-autodelete
              simplelogin
              bitwarden
            ];
          };

          Sensitive = {
            id = 2;
            settings = socksProxy 1082;
            extensions.packages = with firefox-addons; [
              ublock-origin
              canvasblocker
              clearurls
              cookie-autodelete
              bitwarden
            ];
          };

          Academic = {
            id = 3;
            settings = {
              "network.proxy.type" = 2;
              "network.proxy.autoconfig_url" = pacUrl "academic";
              "network.proxy.socks" = "127.0.0.1";
              "network.proxy.socks_port" = 1083;
              "network.proxy.socks_remote_dns" = true;
            };
            extensions.packages = with firefox-addons; [
              ublock-origin
              multi-account-containers
              web-clipper-obsidian
              zotero-connector
              bitwarden
            ];
          };

          Social = {
            id = 4;
            settings = socksProxy 1084;
            extensions.packages = with firefox-addons; [
              ublock-origin
              multi-account-containers
              cookie-autodelete
              chrome-mask
              bitwarden
            ];
          };
        };
      }
    )
  ];
}
