# kimi-claude-proxy (nix-darwin entry point). Imports common.nix for the
# package + fish function, and defines the launchd user agent.
# See default.nix for full context / why this proxy exists.
#
# Used by: hosts/germanium/configuration.nix
{ kimiClaudeProxyBin, ... }:
{
  imports = [ ./common.nix ];

  launchd.user.agents.kimi-claude-proxy = {
    serviceConfig = {
      ProgramArguments = [
        "${kimiClaudeProxyBin}/bin/kimi-claude-proxy"
        "--port"
        "8787"
      ];
      RunAtLoad = true;
      KeepAlive = true;
      StandardOutPath = "/tmp/kimi-claude-proxy.log";
      StandardErrorPath = "/tmp/kimi-claude-proxy.err";
    };
  };
}
