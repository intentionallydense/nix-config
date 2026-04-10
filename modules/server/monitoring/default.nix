# Monitoring stack: Prometheus collects metrics, Grafana displays them.
# Node exporter exposes system metrics (CPU, RAM, disk, temps, network).
# Used by: carbon.
{ config, ... }:
{
  # Prometheus — time-series metrics database
  services.prometheus = {
    enable = true;
    port = 9090;

    # Scrape node exporter for system metrics
    scrapeConfigs = [
      {
        job_name = "node";
        static_configs = [
          { targets = [ "localhost:9100" ]; }
        ];
      }
    ];

    exporters = {
      # Node exporter — exposes CPU, memory, disk, network, temperature metrics
      node = {
        enable = true;
        port = 9100;
        enabledCollectors = [
          "systemd"    # systemd service states
          "processes"  # process counts
        ];
      };
    };
  };

  # Grafana — dashboards and visualisation
  services.grafana = {
    enable = true;
    settings = {
      server = {
        http_addr = "0.0.0.0"; # Listen on all interfaces (access gated by Tailscale firewall)
        http_port = 3000;
        domain = "grafana.carbon";
      };

      # Secret key for signing — read from sops-managed secret file
      security.secret_key = "$__file{${config.sops.secrets.grafana_secret_key.path}}";

      # Disable login for local/Tailscale access — single-user server
      "auth.anonymous" = {
        enabled = true;
        org_role = "Admin";
      };
    };

    # Auto-provision Prometheus as a data source so it works out of the box
    provision = {
      datasources.settings.datasources = [
        {
          name = "Prometheus";
          type = "prometheus";
          url = "http://localhost:9090";
          isDefault = true;
        }
      ];
    };
  };
}
