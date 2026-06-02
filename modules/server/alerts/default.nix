# Active health alerts → ntfy (phone push). Checks live system state every
# 15 min (disk / failed units / SMART / CPU temp) and pushes a notification
# when something crosses a threshold, plus an "all clear" when it recovers.
#
# Deliberately NOT routed through Prometheus/Alertmanager: checking the system
# directly means alerting keeps working even if Prometheus is down, and we get
# full control over the ntfy message (Alertmanager → public ntfy.sh needs a
# formatting bridge to avoid raw-JSON notifications). Prometheus + Grafana stay
# for dashboards and history.
#
# The ntfy topic is a sops secret because the nix-config repo is public.
# Used by: carbon.
{ pkgs, config, ... }:
let
  diskThreshold = 85;   # percent
  tempThreshold = 92;   # °C
  renotify = 21600;     # re-alert an unchanged problem after this many seconds (6h)

  alertScript = pkgs.writeShellScript "carbon-alert-check" ''
    set -uo pipefail

    NTFY_URL="$(cat ${config.sops.secrets.ntfy_alert_url.path})"
    STATE_DIR="/var/lib/carbon-alerts"
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

    # --- SMART health (alert only on explicit failure; USB bridges may not
    #     report SMART at all, and we don't want false alarms) ---
    for dev in /dev/nvme0 /dev/sda; do
      [ -e "$dev" ] || continue
      smart_out="$(smartctl -H "$dev" 2>/dev/null)" || true
      if printf '%s' "$smart_out" | grep -qiE 'FAILED|FAILING'; then
        problems+=("SMART FAILED on $dev")
      fi
    done

    # --- CPU temperature (max across thermal zones) ---
    maxtemp=0
    for z in /sys/class/thermal/thermal_zone*/temp; do
      [ -r "$z" ] || continue
      t=$(( $(cat "$z") / 1000 ))
      [ "$t" -gt "$maxtemp" ] && maxtemp="$t"
    done
    if [ "$maxtemp" -ge ${toString tempThreshold} ]; then
      problems+=("CPU temp ''${maxtemp}°C")
    fi

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
        send "carbon: ''${#problems[@]} issue(s)" "high" "warning" "$(printf '%s\n' "''${problems[@]}")"
        printf '%s' "$cur" > "$STATE_DIR/hash"
        printf '%s' "$now" > "$STATE_DIR/time"
      fi
    else
      if [ -n "$laststate" ] && [ "$laststate" != "ok" ]; then
        send "carbon: all clear" "default" "white_check_mark" "All monitored checks are back to normal."
      fi
      printf '%s' "$cur" > "$STATE_DIR/hash"
      printf '%s' "$now" > "$STATE_DIR/time"
    fi

    # heartbeat — tell healthchecks the checker ran (also proves carbon is up).
    curl -fsS -m 10 "$(cat ${config.sops.secrets.hc_heartbeat_url.path})" >/dev/null || true
  '';
in
{
  sops.secrets.ntfy_alert_url = {
    owner = "root";
    mode = "0400";
  };
  # healthchecks.io heartbeat ping URL (pinged every run → proves the checker
  # ran AND carbon is up). 0444; kept out of the public repo via sops.
  sops.secrets.hc_heartbeat_url.mode = "0444";

  systemd.services.carbon-alert-check = {
    description = "Check carbon health and push ntfy alerts on problems";
    # smartctl, systemctl, thermal reads run as root (default — no User=).
    path = with pkgs; [ coreutils gawk util-linux systemd smartmontools curl gnugrep ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = alertScript;
      StateDirectory = "carbon-alerts";
    };
  };

  systemd.timers.carbon-alert-check = {
    description = "Run carbon health checks every 15 minutes";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "3min";
      OnUnitActiveSec = "15min";
      Persistent = true;
    };
  };
}
