# Hermes Agent (Nous Research) — read-only personal assistant.
# Runs in a hardened podman container: read-only rootfs, no new privileges,
# egress filtered to a whitelist via a dedicated nftables table.
#
# Used by: carbon host configuration.
# Import in configuration.nix: ../../modules/server/hermes
#
# Surprising bits:
# - nftables rules live in a separate `inet hermes` table so they don't
#   conflict with carbon's existing networking.firewall rules.
# - Egress IP sets are populated at boot by hermes-resolve-egress.service.
#   If upstream IPs rotate, the container fails loudly (by design — the
#   user explicitly wants this rather than silent reachability to new IPs).
# - Container UID is 10000 (baked into the upstream image); data dir on
#   the host is chowned to a `hermes` system user with the same UID.
# - DeepSeek uses an OpenAI-compatible API; Hermes reads OPENAI_API_KEY for it.
# - Telegram chat-ID restriction is enforced at the config layer (not LLM layer).
# - The container command defaults to the image entrypoint. If the Telegram
#   gateway doesn't start automatically, add `cmd = ["hermes" "telegram"]`
#   to the container config. This is flagged as a judgment call — the upstream
#   docs are ambiguous about the exact startup command for Telegram gateway mode.

{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.hermes;

  # ---- Config file generation -----------------------------------------------
  # Generated from module options so telegramChatId and allowed paths are
  # baked in at eval time rather than being runtime substitutions.
  yaml = pkgs.formats.yaml {};

  hermesConfigFile = yaml.generate "hermes-config.yaml" {
    model = {
      # DeepSeek uses an OpenAI-compatible endpoint.
      # Swap provider/base_url here to change LLM providers — one place.
      default = "deepseek/deepseek-chat";
      provider = "openrouter";
      # api_key is injected via OPENROUTER_API_KEY in the env file.
    };

    toolsets = {
      # Write-class and execution toolsets are disabled entirely.
      # Anything not in this disabled list that isn't in enabled is also off.
      disabled = [
        "terminal"        # shell execution — disabled
        "code_execution"  # code runner — disabled
        "browser"         # browser automation — disabled
        "image_gen"       # image generation — disabled
        "vision"          # vision tools — disabled
        "delegation"      # subagent spawning (requires Docker socket) — disabled
        "cronjob"         # scheduled tasks — disabled
        "hooks"           # event hooks — disabled
      ];
      enabled = [
        "memory"   # persistent memory across sessions
        "skills"   # auto-generated skill reuse
        "web"      # Tavily web search (read-only)
        "file"     # file reads from allowed_paths (read-only enforced below)
        "todo"     # task list (writes only to /opt/data)
      ];
    };

    web = {
      # TAVILY_API_KEY injected via env file.
      provider = "tavily";
    };

    file = {
      # All write operations disabled at the tool level.
      # allowed_paths maps to the container-side mount points set up via
      # cfg.readOnlyMounts. Keep this list in sync with those mounts.
      write_enabled = false;
      allowed_paths = map (m: m.dest) cfg.readOnlyMounts;
    };

    telegram = {
      # TELEGRAM_BOT_TOKEN injected via env file.
      # Only the specified chat ID can trigger or receive messages.
      # Any message from another chat ID is silently dropped by Hermes.
      allowed_chat_ids = [ cfg.telegramChatId ];
    };

    memory = {
      enabled = true;
      path = "/opt/data/memories";
    };

    skills = {
      enabled = true;
      path = "/opt/data/skills";
    };

    # API server disabled — gateway is Telegram only, no HTTP exposure.
    api_server = {
      enabled = false;
    };
  };

  # ---- nftables ruleset file ------------------------------------------------
  # Written to the nix store; loaded by hermes-nft-setup.service.
  # Separate inet hermes table — does NOT touch the main inet filter table.
  nftRules = pkgs.writeText "hermes-egress.nft" ''
    # Hermes egress filter — loaded by hermes-nft-setup.service.
    #
    # Separate table so it doesn't interact with carbon's existing
    # networking.firewall rules (which live in inet filter at priority 0).
    #
    # The forward chain hooks at priority 10 (runs after the main filter).
    # Only traffic from the hermes container subnet is affected; everything
    # else hits the `return` rule immediately and is unaffected.
    table inet hermes {

      # egress_whitelist: populated at boot by hermes-resolve-egress.service.
      # Entries have a 24h timeout — if the resolve service hasn't run within
      # 24h, entries expire and the container loses API access (fail-loud).
      # Refresh manually: systemctl restart hermes-resolve-egress
      set egress_whitelist {
        type ipv4_addr
        flags timeout
      }

      chain forward {
        type filter hook forward priority 10; policy accept;

        # Only restrict traffic from the hermes container subnet.
        # All other traffic is returned immediately — no side effects.
        ip saddr != ${cfg.containerSubnet} return

        # Allow established/related return traffic.
        ct state established,related accept

        # DNS — Cloudflare resolver only (both UDP and TCP for large responses).
        ip daddr ${cfg.dnsServer} udp dport 53 accept
        ip daddr ${cfg.dnsServer} tcp dport 53 accept

        # NTP — single server (default: Cloudflare NTP at 162.159.200.1).
        ip daddr ${cfg.ntpServer} udp dport 123 accept

        # HTTPS to whitelisted API endpoints only.
        # Set populated by hermes-resolve-egress.service at boot.
        # Allowed: api.deepseek.com, api.telegram.org, api.tavily.com
        ip daddr @egress_whitelist tcp dport 443 accept

        # Drop everything else from the container subnet.
        # If DeepSeek or Telegram rotate to a new IP, the container fails
        # here rather than silently reaching an unknown address.
        drop
      }
    }
  '';

  # ---- Egress resolver script -----------------------------------------------
  resolveScript = pkgs.writeShellScript "hermes-resolve-egress" ''
    set -euo pipefail

    NFT="${pkgs.nftables}/bin/nft"
    DIG="${pkgs.dnsutils}/bin/dig"

    # Flush existing set before repopulating.
    # Fails fast if the hermes table doesn't exist yet — that's a bug in
    # service ordering, not a transient error.
    $NFT flush set inet hermes egress_whitelist

    resolve_and_add() {
      local domain="$1"
      local ips

      # Query A records; +short gives one IP per line.
      ips=$($DIG +short +timeout=10 +tries=3 "$domain" A \
            | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')

      if [ -z "$ips" ]; then
        echo "ERROR: could not resolve $domain" >&2
        echo "The hermes container will be blocked from reaching this endpoint." >&2
        return 1
      fi

      for ip in $ips; do
        echo "Whitelisting $ip for $domain"
        $NFT add element inet hermes egress_whitelist "{ $ip timeout 24h }"
      done
    }

    ${concatMapStringsSep "\n    " (d: ''resolve_and_add "${d}"'') cfg.egressDomains}

    echo "Egress whitelist populated successfully."
    $NFT list set inet hermes egress_whitelist
  '';

  # ---- Network setup script -------------------------------------------------
  networkScript = pkgs.writeShellScript "hermes-network-create" ''
    set -euo pipefail
    if ! ${pkgs.podman}/bin/podman network inspect hermes-net &>/dev/null; then
      ${pkgs.podman}/bin/podman network create \
        --driver bridge \
        --subnet ${cfg.containerSubnet} \
        hermes-net
      echo "Created podman network hermes-net (${cfg.containerSubnet})"
    else
      echo "Network hermes-net already exists, skipping."
    fi
  '';

  networkDestroyScript = pkgs.writeShellScript "hermes-network-destroy" ''
    ${pkgs.podman}/bin/podman network rm -f hermes-net 2>/dev/null || true
  '';

in {

  # ============================================================================
  # Module options
  # ============================================================================

  options.services.hermes = {

    enable = mkEnableOption "Hermes Agent read-only personal assistant";

    image = mkOption {
      type = types.str;
      default = "docker.io/nousresearch/hermes-agent:v2026.4.8";
      description = ''
        Pinned container image. Never use :latest — pin to a specific tag.
        To upgrade: change the tag here and run nixos-rebuild switch.
      '';
    };

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/hermes";
      description = ''
        Persistent data directory on the host. Mounted as /opt/data inside
        the container. Contains memories, skills, sessions, state.db, logs.
        Owner: hermes system user (UID 10000).
      '';
    };

    telegramChatId = mkOption {
      type = types.int;
      example = 123456789;
      description = ''
        Telegram chat ID Hermes is permitted to message.
        All other chat IDs are rejected at the config layer.
        Find yours by messaging @userinfobot on Telegram.
      '';
    };

    readOnlyMounts = mkOption {
      type = types.listOf (types.submodule {
        options = {
          source = mkOption {
            type = types.path;
            description = "Absolute path on the host to bind-mount read-only.";
          };
          dest = mkOption {
            type = types.str;
            description = "Mount point inside the container (e.g. /mnt/docs).";
          };
        };
      });
      default = [];
      example = literalExpression ''
        [
          { source = "/home/alice/Documents"; dest = "/mnt/docs"; }
          { source = "/home/alice/projects";  dest = "/mnt/projects"; }
        ]
      '';
      description = ''
        Host paths to expose read-only inside the container.
        These are the only filesystem paths Hermes can read (besides /opt/data).
        The dest paths must also appear in the Hermes file.allowed_paths config
        — they are wired automatically via this module.
      '';
    };

    # --- Network options -------------------------------------------------------

    containerSubnet = mkOption {
      type = types.str;
      default = "172.28.0.0/28";
      description = ''
        Subnet for the hermes podman bridge network.
        Must not collide with existing container networks or LAN subnets.
        nftables egress rules match traffic from this range.
      '';
    };

    dnsServer = mkOption {
      type = types.str;
      default = "1.1.1.1";
      description = "DNS resolver the container is allowed to reach (UDP/TCP 53).";
    };

    ntpServer = mkOption {
      type = types.str;
      default = "162.159.200.1"; # time.cloudflare.com
      description = "NTP server IP (UDP 123). Default: Cloudflare NTP.";
    };

    egressDomains = mkOption {
      type = types.listOf types.str;
      default = [
        "api.deepseek.com"
        "api.telegram.org"
        "api.tavily.com"
      ];
      description = ''
        Hostnames resolved at boot to populate the egress IP whitelist.
        Only add exactly the hostnames the agent needs — no wildcards.
        If an API provider adds a new subdomain, it will be blocked until
        you add it here and run: systemctl restart hermes-resolve-egress
      '';
    };

  };

  # ============================================================================
  # Implementation
  # ============================================================================

  config = mkIf cfg.enable {

    # -- System user -----------------------------------------------------------
    # UID/GID 10000 matches the container image's internal hermes user,
    # so volume files are accessible without ownership mismatches.
    users.users.hermes = {
      isSystemUser = true;
      group = "hermes";
      uid = 10000;
      home = cfg.dataDir;
      description = "Hermes agent service account";
    };
    users.groups.hermes = {
      gid = 10000;
    };

    # -- Persistent data directories -------------------------------------------
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir}            0750 hermes hermes -"
      "d ${cfg.dataDir}/memories   0750 hermes hermes -"
      "d ${cfg.dataDir}/skills     0750 hermes hermes -"
      "d ${cfg.dataDir}/sessions   0750 hermes hermes -"
      "d ${cfg.dataDir}/logs       0750 hermes hermes -"
    ];

    # -- Hermes config file ---------------------------------------------------
    # Deployed to /etc/hermes/config.yaml on the host, then bind-mounted
    # read-only into the container at /opt/data/config.yaml.
    environment.etc."hermes/config.yaml" = {
      source = hermesConfigFile;
      # 0444: root owns it (no secrets here — secrets are in the env file),
      # but UID 10000 inside the container needs to read it.
      mode = "0444";
    };

    # -- sops-nix secrets ------------------------------------------------------
    # Decrypts hermes_* keys from secrets.yaml and assembles an env file
    # that podman injects into the container at startup.
    # The secrets must exist in your sops.defaultSopsFile (secrets/secrets.yaml).
    sops.secrets.deepseek_hermes_openrouter_key = {};
    sops.secrets.deepseek_hermes_telegram_key = {};
    sops.secrets.deepseek_hermes_tavily_key = {};

    # Rendered env file — root-readable, passed to podman via environmentFiles.
    # Uses sops-nix templates to interpolate multiple secrets into one file.
    sops.templates."hermes.env" = {
      content = ''
        OPENROUTER_API_KEY=${config.sops.placeholder.deepseek_hermes_openrouter_key}
        TELEGRAM_BOT_TOKEN=${config.sops.placeholder.deepseek_hermes_telegram_key}
        TAVILY_API_KEY=${config.sops.placeholder.deepseek_hermes_tavily_key}
      '';
      # Default path: /run/secrets-rendered/hermes.env
      # Readable only by root (podman runs as root for the system service).
      mode = "0400";
    };

    # -- Podman network --------------------------------------------------------
    # Creates a named bridge network with a fixed subnet so nftables rules
    # have a stable IP range to match on.
    # ExecStop removes the network when the service stops (e.g. on rollback).
    systemd.services.hermes-network-setup = {
      description = "Create hermes podman bridge network";
      after = [ "network.target" ];
      before = [ "podman-hermes.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = networkScript;
        ExecStop = networkDestroyScript;
      };
    };

    # -- nftables egress rules -------------------------------------------------
    # Loads the hermes nft table. Runs before the resolve service and the
    # container so the set exists when resolve_and_add runs.
    systemd.services.hermes-nft-setup = {
      description = "Load hermes nftables egress filter table";
      after = [ "network.target" ];
      before = [ "hermes-resolve-egress.service" "podman-hermes.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "hermes-nft-load" ''
          set -euo pipefail
          NFT="${pkgs.nftables}/bin/nft"
          # Idempotent: delete existing table if present, then reload.
          if $NFT list table inet hermes &>/dev/null 2>&1; then
            $NFT delete table inet hermes
          fi
          $NFT -f ${nftRules}
          echo "hermes nftables table loaded."
        '';
        # Remove the hermes table on stop — clean rollback.
        ExecStop = "${pkgs.nftables}/bin/nft delete table inet hermes";
      };
    };

    # -- Egress IP resolver ----------------------------------------------------
    # Resolves egressDomains and populates the nftables whitelist set.
    # Runs at boot before the container starts. Fails the container startup
    # if any domain can't be resolved (network outage, DNS failure, etc.).
    # Refresh after IP rotation: systemctl restart hermes-resolve-egress
    systemd.services.hermes-resolve-egress = {
      description = "Resolve hermes egress domains into nftables whitelist";
      after = [ "network-online.target" "hermes-nft-setup.service" ];
      wants = [ "network-online.target" ];
      before = [ "podman-hermes.service" ];
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.nftables pkgs.dnsutils ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = resolveScript;
      };
    };

    # -- Container -------------------------------------------------------------
    virtualisation.oci-containers = {
      backend = "podman";
      containers.hermes = {
        image = cfg.image;

        # entrypoint.sh does `exec hermes "$@"` — pass the gateway subcommand.
        cmd = [ "gateway" "run" ];

        # Env file: decrypted by sops-nix at activation, read by podman at start.
        environmentFiles = [ config.sops.templates."hermes.env".path ];

        volumes = [
          # Persistent data — read-write for memories, skills, sessions, state.db
          "${cfg.dataDir}:/opt/data:rw"
          # Config — read-only so the container can't modify its own tool config
          "/etc/hermes/config.yaml:/opt/data/config.yaml:ro"
        ] ++ (map (m: "${m.source}:${m.dest}:ro") cfg.readOnlyMounts);

        extraOptions = [
          # Hardening
          "--read-only"
          "--tmpfs=/tmp:rw,noexec,nosuid"
          # Python/Telegram library writes cache to the hermes user's home .local
          "--tmpfs=/opt/hermes/.local:rw"
          "--cap-drop=ALL"
          "--security-opt=no-new-privileges"

          # Identity: run as UID/GID 10000 (matches hermes user in image)
          "--user=10000:10000"

          # Network: use the fixed-subnet bridge network so nftables rules apply.
          # --dns overrides podman's default resolver; nftables allows DNS only to
          # this IP, so the container can't reach any other resolver.
          "--network=hermes-net"
          "--dns=${cfg.dnsServer}"

          # No auto-update inside the container — pin is in cfg.image
        ];
      };
    };

    # Wire container startup after all prep services are ready.
    # mkAfter appends to the list that virtualisation.oci-containers generates,
    # so we don't overwrite its existing after/requires entries.
    systemd.services.podman-hermes = {
      after = lib.mkAfter [
        "hermes-network-setup.service"
        "hermes-nft-setup.service"
        "hermes-resolve-egress.service"
      ];
      requires = lib.mkAfter [
        "hermes-network-setup.service"
        "hermes-nft-setup.service"
        "hermes-resolve-egress.service"
      ];
    };

    # Ensure podman is available at the system level.
    # Only enables podman — no global settings that would affect other containers.
    virtualisation.podman.enable = true;

  };
}
