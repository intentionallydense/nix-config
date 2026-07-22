# slskd Soulseek-connection watchdog → self-heal + healthchecks.io.
#
# Covers the failure mode the alerts module structurally can't see: slskd's
# process stays up and its HTTP API keeps answering 200 (so the liveness probe
# in modules/alerts passes), but the Soulseek *server connection* behind it is
# dead. Observed 2026-07-22: a wireproxy-mullvad WireGuard re-handshake dropped
# the TCP session and slskd (0.24.5) wedged in "Disconnecting" indefinitely —
# no reconnect attempts, no log output, every search returning 409. Only a
# service restart recovers it, and it will recur on any tunnel blip.
#
# Behavior, tuned to self-heal silently and only page when self-healing fails:
#   - healthy (Connected + LoggedIn): success ping to healthchecks → the check
#     stays green; if the watchdog itself stops running, grace expiry alerts.
#   - unhealthy: no success ping; after 2 consecutive bad checks (~4 min, so a
#     transient reconnect doesn't trigger it) restart slskd and record it via
#     the /log ping endpoint (visible in check history, no alert). Re-attempt
#     every ~30 min, not every run — no restart loops while Soulseek itself or
#     the tunnel is down.
#   - still unhealthy 5 checks in (~10 min, restart didn't help): explicit
#     /fail ping → healthchecks alerts immediately, state in the ping body.
#   - slskd unit not active at all: leave it alone (respect a manual stop; the
#     failed-units sweep in modules/alerts owns crashed units) and send no
#     ping — a deliberately stopped slskd surfaces as grace expiry, which is
#     the right nudge if it's been forgotten.
#
# Provision the check with period = timer interval (2 min), grace ≥ 10 min.
# Used by: tin.
{ pkgs, config, ... }:
let
  strikesBeforeRestart = 2;   # consecutive bad checks before restarting
  strikesBeforeAlert = 5;     # ... before an explicit /fail alert
  restartRetryEvery = 15;     # re-attempt restart every N strikes (~30 min)

  watchdogScript = pkgs.writeShellScript "slskd-watchdog" ''
    set -uo pipefail

    API_KEY="$(cat ${config.sops.secrets.slskd_api_key.path})"
    HC_URL="$(cat ${config.sops.secrets.hc_slskd_watchdog_url.path})"
    STATE_DIR="/var/lib/slskd-watchdog"
    mkdir -p "$STATE_DIR"

    hc() { # $1=path suffix ("" | /log | /fail) $2=body
      curl -fsS -m 10 -d "$2" "$HC_URL$1" >/dev/null || true
    }

    # Respect a manual stop: no restart, no ping (grace expiry will nudge).
    if ! systemctl is-active --quiet slskd; then
      exit 0
    fi

    state="$(curl -fsS -m 10 -H "X-API-Key: $API_KEY" \
      http://localhost:5030/api/v0/server | jq -r '.state' || echo api-unreachable)"

    case "$state" in
      *Connected*LoggedIn*)
        rm -f "$STATE_DIR/strikes"
        hc "" "state=$state"
        exit 0
        ;;
    esac

    strikes=0
    [ -f "$STATE_DIR/strikes" ] && strikes="$(cat "$STATE_DIR/strikes")"
    strikes=$(( strikes + 1 ))
    printf '%s' "$strikes" > "$STATE_DIR/strikes"

    if [ "$strikes" -eq ${toString strikesBeforeRestart} ] ||
       [ "$(( (strikes - ${toString strikesBeforeRestart}) % ${toString restartRetryEvery} ))" -eq 0 ]; then
      hc "/log" "restarting slskd (state was: $state, strike $strikes)"
      systemctl restart slskd || hc "/fail" "restart of slskd failed (state: $state)"
    elif [ "$strikes" -ge ${toString strikesBeforeAlert} ]; then
      hc "/fail" "slskd unhealthy after restart: $state (strike $strikes)"
    fi
  '';
in
{
  # healthchecks.io ping URL for this check; kept out of the public repo via
  # sops, same pattern as hc_heartbeat_url in modules/alerts.
  sops.secrets.hc_slskd_watchdog_url = {
    owner = "root";
    mode = "0400";
  };

  systemd.services.slskd-watchdog = {
    description = "Restart slskd when its Soulseek connection wedges";
    # systemctl runs as root (default — no User=); slskd_api_key is root/0400.
    path = with pkgs; [ coreutils curl jq systemd ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = watchdogScript;
      StateDirectory = "slskd-watchdog";
    };
  };

  systemd.timers.slskd-watchdog = {
    description = "Check slskd Soulseek connection every 2 minutes";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "2min";
      Persistent = false; # a missed window while tin is off is meaningless
    };
  };
}
