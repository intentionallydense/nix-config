# kimi-claude-proxy — bridge Claude Code harness to Kimi For Coding subscription.
#
# NixOS entry point: imports common.nix for the package + fish function, and
# defines the systemd user service. macOS hosts should import ./darwin.nix
# instead (which wires launchd).
#
# Why this exists:
#   Moonshot's api.kimi.com/coding/v1 is Anthropic-compatible and explicitly
#   supports Claude Code, but (a) doesn't implement GET /v1/models/{id} which
#   Claude Code needs for model validation, and (b) uses OAuth tokens that
#   expire every 15 minutes. The proxy fakes the former and transparently
#   refreshes the latter. Pointed at via ANTHROPIC_BASE_URL in mgkimi.
#
# Used by: hosts/carbon/configuration.nix
{ kimiClaudeProxyBin, ... }:
{
  imports = [ ./common.nix ];

  systemd.user.services.kimi-claude-proxy = {
    description = "Kimi For Coding ↔ Claude Code Anthropic-format proxy";
    wantedBy = [ "default.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${kimiClaudeProxyBin}/bin/kimi-claude-proxy --port 8787";
      Restart = "on-failure";
      RestartSec = 5;
      StandardOutput = "journal";
      StandardError = "journal";
    };
  };
}
