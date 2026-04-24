# Shared bits of kimi-claude-proxy: the wrapped Python binary and the mgkimi
# fish function. Platform-specific service definitions live in default.nix
# (NixOS/systemd) and darwin.nix (nix-darwin/launchd).
{ pkgs, ... }:

let
  pythonEnv = pkgs.python313.withPackages (ps: [ ps.aiohttp ]);
  proxyBin = pkgs.writeShellScriptBin "kimi-claude-proxy" ''
    exec ${pythonEnv}/bin/python3 ${./kimi-claude-proxy.py} "$@"
  '';
in
{
  _module.args.kimiClaudeProxyBin = proxyBin;

  environment.systemPackages = [ proxyBin ];

  home-manager.sharedModules = [
    ({ ... }: {
      xdg.configFile."fish/functions/mgkimi.fish".source = ./mgkimi.fish;
    })
  ];
}
