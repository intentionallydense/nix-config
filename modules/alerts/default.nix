# Active health alerts → ntfy (phone push) + healthchecks.io dead-man's-switch.
# Checks live system state every 15 min and pushes a notification when
# something crosses a threshold, plus an "all clear" when it recovers.
#
# Two complementary layers:
#   - ntfy (push FROM tin): disk usage, failed systemd units, HTTP liveness of
#     the serving stack. Catches "tin is up but something on it is broken" —
#     including failed oneshot timers (music-auto-import etc.), which land in
#     `systemctl --failed` and get swept up here with no per-unit hooks.
#   - healthchecks.io (ping FROM tin, alert from outside): the checker pings a
#     heartbeat URL every run. If tin dies, loses network, or the timer stops
#     firing, the pings stop and healthchecks alerts — the case ntfy-from-tin
#     can never catch.
#
# Deliberately NOT routed through Prometheus/Alertmanager: checking the system
# directly means alerting keeps working even if Prometheus is down, and we get
# full control over the ntfy message. Prometheus + Grafana stay for dashboards.
#
# Carbon-era checks dropped for a cloud VPS: SMART (virtual disk, no data) and
# CPU temp (no thermal zones in a Hetzner VM). History: `fleet-final` tag.
#
# The ntfy topic is a sops secret because the nix-config repo is public.
# Used by: tin.
{ pkgs, config, ... }:
let
  diskThreshold = 85;   # percent
  renotify = 21600;     # re-alert an unchanged problem after this many seconds (6h)

  # Serving-stack liveness probes: "name|url", checked with a plain curl.
  # Catches hung-but-running services that the failed-units sweep misses
  # (Restart=on-failure keeps them "active" while they flap or wedge).
  # All endpoints are unauthenticated health/root paths on localhost.
  httpChecks = [
    "navidrome|http://localhost:4533/ping"
    "music-shelf|http://localhost:4534/"
    "slskd|http://localhost:5030/"
    "calibre-web|http://localhost:8084/"
    "immich|http://localhost:2283/api/server/ping"
    "synapse|http://localhost:8008/health"
    "grafana|http://localhost:3000/api/health"
  ];

  alertScript = pkgs.writeShellScript "tin-alert-check" ''
    set -uo pipefail

    NTFY_URL="$(cat ${config.sops.secrets.ntfy_alert_url.path})"
    STATE_DIR="/var/lib/tin-alerts"
    mkdir -p "$STATE_DIR"

    problems=()

    # --- disk usage ---
    while read -r use mount; do
      pct="''${use%\%}"
      if [ "$pct" -ge ${toString diskThreshold} ]; then
        problems+=("disk $mount at $use")
      fi
    done < <(df --output=pcent,target -x tmpfs -x devtmpfs -x efivarfs 2>/dev/null | tail -n +2)

    # --- failed systemd units ---
    failed="$(systemctl --failed --no-legend --plain 2>/dev/null | awk '{print $1}' | paste -sd, -)"
    if [ -n "$failed" ]; then
      problems+=("failed units: $failed")
    fi

    # --- HTTP liveness of the serving stack ---
    for check in ${toString (map (c: "'${c}'") httpChecks)}; do
      name="''${check%%|*}"
      url="''${check#*|}"
      if ! curl -fsS -m 10 -o /dev/null "$url"; then
        problems+=("$name not responding at $url")
      fi
    done

    # --- notify on change, or re-notify an unchanged problem after the interval ---
    now="$(date +%s)"
    if [ "''${#problems[@]}" -gt 0 ]; then
      cur="$(printf '%s\n' "''${problems[@]}" | sort | sha256sum | awk '{print $1}')"
    else
      cur="ok"
    fi

    laststate=""; lasttime=0
    [ -f "$STATE_DIR/hash" ] && laststate="$(cat "$STATE_DIR/hash")"
    [ -f "$STATE_DIR/time" ] && lasttime="$(cat "$STATE_DIR/time")"

    send() { # $1=title $2=priority $3=tags $4=body
      curl -s -m 10 -H "Title: $1" -H "Priority: $2" -H "Tags: $3" -d "$4" "$NTFY_URL" >/dev/null || true
    }

    if [ "$cur" != "ok" ]; then
      if [ "$cur" != "$laststate" ] || [ "$(( now - lasttime ))" -ge ${toString renotify} ]; then
        send "tin: ''${#problems[@]} issue(s)" "high" "warning" "$(printf '%s\n' "''${problems[@]}")"
        printf '%s' "$cur" > "$STATE_DIR/hash"
        printf '%s' "$now" > "$STATE_DIR/time"
      fi
    else
      if [ -n "$laststate" ] && [ "$laststate" != "ok" ]; then
        send "tin: all clear" "default" "white_check_mark" "All monitored checks are back to normal."
      fi
      printf '%s' "$cur" > "$STATE_DIR/hash"
      printf '%s' "$now" > "$STATE_DIR/time"
    fi

    # heartbeat — tell healthchecks the checker ran (also proves tin is up).
    # Dead-man's-switch: healthchecks alerts when these pings STOP arriving.
    curl -fsS -m 10 "$(cat ${config.sops.secrets.hc_heartbeat_url.path})" >/dev/null || true
  '';
in
{
  sops.secrets.ntfy_alert_url = {
    owner = "root";
    mode = "0400";
  };
  # healthchecks.io heartbeat ping URL (pinged every run → proves the checker
  # ran AND tin is up). 0444; kept out of the public repo via sops.
  sops.secrets.hc_heartbeat_url.mode = "0444";

  systemd.services.tin-alert-check = {
    description = "Check tin health and push ntfy alerts on problems";
    # systemctl runs as root (default — no User=).
    path = with pkgs; [ coreutils gawk util-linux systemd curl ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = alertScript;
      StateDirectory = "tin-alerts";
    };
  };

  systemd.timers.tin-alert-check = {
    description = "Run tin health checks every 15 minutes";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "3min";
      OnUnitActiveSec = "15min";
      Persistent = true;
    };
  };
}
