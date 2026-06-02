# Daily briefing assembly (user service + timer, runs 05:00). Migrated into the
# flake on 2026-06-01 from the hand-installed units at
# ~/.config/systemd/user/claude-briefing.{service,timer}.
#
# Runs as the user (lingering is enabled, so it fires headless) via the conda-env
# python that holds the pip-installed `briefing` package. The conda env itself is
# imperative (not nixified) — only the unit + timer are declarative here, which
# is the whole point of the migration: reproducible scheduling, hand-managed deps.
# (The briefing web UI, briefing-server.service, is still a hand-installed user
# unit — migrate similarly if/when desired.)
#
# Pings the carbon-briefing healthchecks.io check on success (dead-man's-switch).
#
# IMPORTANT after first rebuild: the old hand-installed units in
# ~/.config/systemd/user/ shadow these (user config dir outranks /etc/systemd/user),
# so rename them away and reload — see the migration notes in chat.
# Used by: carbon.
{ pkgs, config, username, ... }:
{
  # 0444: read by the fluoride user service; low-sensitivity, out of the public repo via sops.
  sops.secrets.hc_briefing_url.mode = "0444";

  systemd.user.services.claude-briefing = {
    description = "Daily Briefing Assembly";
    serviceConfig = {
      Type = "oneshot";
      WorkingDirectory = "/home/${username}/briefing";
      ExecStart = "/home/${username}/miniconda3/envs/claude-ai/bin/python -m briefing.cli assemble";
      Environment = "HOME=/home/${username}";
      # Ping healthchecks.io on success — ExecStartPost runs only if the assembly
      # succeeded. `-` so a failed ping never marks the briefing itself failed.
      ExecStartPost = "-${pkgs.writeShellScript "hc-ping-briefing" ''
        ${pkgs.curl}/bin/curl -fsS -m 10 "$(cat ${config.sops.secrets.hc_briefing_url.path})" >/dev/null
      ''}";
    };
  };

  systemd.user.timers.claude-briefing = {
    description = "Run daily briefing assembly at 05:00";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 05:00:00";
      Persistent = true;
    };
  };
}
