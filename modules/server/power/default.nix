# Always-on laptop server power management.
# Disables suspend/hibernate, ignores lid close, caps battery at 80%.
# Used by: carbon (Dell Latitude 7420 home server).
{ ... }:
{
  # Lid close does nothing — server stays on when lid is shut
  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandleLidSwitchExternalPower = "ignore";
    HandleLidSwitchDocked = "ignore";
  };

  # Disable all sleep states — server should never suspend or hibernate
  systemd.targets = {
    sleep.enable = false;
    suspend.enable = false;
    hibernate.enable = false;
    hybrid-sleep.enable = false;
  };

  # TLP: optimise for always-on AC with 80% charge cap for battery longevity
  services.tlp = {
    enable = true;
    settings = {
      # CPU: full performance on AC (server is always plugged in)
      CPU_SCALING_GOVERNOR_ON_AC = "performance";
      CPU_SCALING_GOVERNOR_ON_BAT = "powersave";

      CPU_ENERGY_PERF_POLICY_ON_AC = "performance";
      CPU_ENERGY_PERF_POLICY_ON_BAT = "power";

      CPU_MIN_PERF_ON_AC = 0;
      CPU_MAX_PERF_ON_AC = 100;
      CPU_MIN_PERF_ON_BAT = 0;
      CPU_MAX_PERF_ON_BAT = 50;

      # Battery longevity: cap charge at 80%.
      # START = resume charging when below this, STOP = stop charging at this.
      START_CHARGE_THRESH_BAT0 = 75;
      STOP_CHARGE_THRESH_BAT0 = 80;
      START_CHARGE_THRESH_BAT1 = 75;
      STOP_CHARGE_THRESH_BAT1 = 80;
    };
  };
}
