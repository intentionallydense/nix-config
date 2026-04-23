# kimi-claude-proxy — bridge Claude Code harness to Kimi For Coding subscription.
#
# Wraps ./kimi-claude-proxy.py in a Python env with aiohttp, runs it as a
# user-level systemd service on port 8787.
#
# Why this exists:
#   Moonshot's api.kimi.com/coding/v1 is Anthropic-compatible and explicitly
#   supports Claude Code, but (a) doesn't implement GET /v1/models/{id} which
#   Claude Code needs for model validation, and (b) uses OAuth tokens that
#   expire every 15 minutes. The proxy fakes the former and transparently
#   refreshes the latter. Pointed at via ANTHROPIC_BASE_URL in mgkimi.
#
# Used by: hosts/carbon/configuration.nix
{ config, lib, pkgs, username, ... }:

let
  pythonEnv = pkgs.python313.withPackages (ps: [ ps.aiohttp ]);
  proxyBin = pkgs.writeShellScriptBin "kimi-claude-proxy" ''
    exec ${pythonEnv}/bin/python3 ${./kimi-claude-proxy.py} "$@"
  '';
in
{
  # Expose the wrapped proxy on PATH (so it can also be invoked manually for debugging)
  environment.systemPackages = [ proxyBin ];

  # Run as user-level systemd service so $HOME resolves to the user's home
  # and credentials reads/writes land in ~/.kimi/credentials/.
  systemd.user.services.kimi-claude-proxy = {
    description = "Kimi For Coding ↔ Claude Code Anthropic-format proxy";
    wantedBy = [ "default.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${proxyBin}/bin/kimi-claude-proxy --port 8787";
      Restart = "on-failure";
      RestartSec = 5;
      StandardOutput = "journal";
      StandardError = "journal";
    };
  };
}
