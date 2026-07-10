# Matrix homeserver (Synapse) + mautrix bridges — tin's self-hosted messaging hub.
#
# server_name: intentiondense.net (apex). Clients (Element, Watch the Matrix)
# talk to https://intentiondense.net; Signal arrives via mautrix-signal linked
# as a secondary device. More bridges (whatsapp, meta, discord) slot in as
# further services.mautrix-* blocks + one line in the db-setup oneshot.
#
# ⚠ PUBLIC EXPOSURE — the one deliberate exception to tin's tailnet-only
# posture (approved 2026-07-06): nginx listens on 80/443 on the public NIC so
# the Apple Watch (no Tailscale on watchOS) can reach the client API from
# anywhere. Surface is kept minimal:
#   - only /_matrix, /_synapse/client and /.well-known/matrix/* are proxied;
#     everything else on the vhost 404s, and non-SNI/bare-IP scans hit a
#     default vhost that rejects the TLS handshake outright.
#   - federation is fully OFF: no federation listener resource, empty
#     federation_domain_whitelist, 8448 closed, no .well-known/matrix/server.
#   - registration closed; the single account is created out-of-band with
#     register_new_matrix_user + the sops registration secret.
# Every other tin service stays gated behind trustedInterfaces=[tailscale0].
#
# Bridge E2EE: allow=true (Element X can only create encrypted rooms, so the
# bot's management room needs it) but default=false — PORTALS stay plaintext
# on OUR server only (Signal↔bridge stays Signal-encrypted, client↔server is
# TLS), which keeps the watch client simple. Flip default if the watch's
# crypto proves solid.
#
# Secrets (declared in the host config, referenced here — repo pattern):
#   synapse_registration_secret — registration_shared_secret_path
#   mautrix_signal_env          — MAUTRIX_SIGNAL_PICKLE_KEY=… (bridge E2EE pickle)
#
# Used by: tin.
{
  config,
  pkgs,
  lib,
  ...
}:
{
  # mautrix bridges link libolm, which nixpkgs flags insecure (2024 advisories;
  # upstream unmaintained). Only the management room uses bridge E2EE here (see
  # header) — permitting is the standard mautrix-on-nixpkgs move.
  # Drop this when mautrix finishes the vodozemac migration.
  nixpkgs.config.permittedInsecurePackages = [ "olm-3.2.16" ];

  # TEMP (2026-07-06): backport the usernameChangeSyncMessage capability from
  # mautrix/signal main. Signal-server 409s device-linking when the new device
  # is missing a capability the account's other devices advertise, and v26.06
  # predates this one — QR login was impossible without it. The bridge merely
  # advertises it (sync messages of that type are ignorable; worst case is a
  # briefly-stale contact username). DROP once nixpkgs ships > v26.06.
  nixpkgs.overlays = [
    (final: prev: {
      mautrix-signal = prev.mautrix-signal.overrideAttrs (old: {
        postPatch = (old.postPatch or "") + ''
          substituteInPlace pkg/signalmeow/provisioning.go \
            --replace-fail \
              '"spqr":               true,' \
              '"spqr": true, "usernameChangeSyncMessage": true,'
        '';
      });
    })
  ];

  # ===========================================================================
  # Synapse — the homeserver. Client API only, loopback; nginx fronts it.
  # ===========================================================================
  services.matrix-synapse = {
    enable = true;
    settings = {
      server_name = "intentiondense.net";
      public_baseurl = "https://intentiondense.net";

      listeners = [
        {
          port = 8008;
          bind_addresses = [ "127.0.0.1" ];
          type = "http";
          tls = false;
          x_forwarded = true; # trust nginx's X-Forwarded-For
          resources = [
            {
              names = [ "client" ]; # deliberately NOT "federation"
              compress = true;
            }
          ];
        }
      ];

      # Belt & braces with the missing federation listener: an empty whitelist
      # refuses federation with every remote server.
      federation_domain_whitelist = [ ];

      enable_registration = false;
      registration_shared_secret_path = config.sops.secrets.synapse_registration_secret.path;

      report_stats = false;
      max_upload_size = "100M"; # match nginx client_max_body_size below

      # database: module default is psycopg2 → db "matrix-synapse" over the
      # local socket, peer-authed as the matrix-synapse service user. The
      # matrix-db-setup oneshot below guarantees the db exists with LC_COLLATE
      # "C" (synapse refuses to start on the cluster default otherwise).
    };
  };

  # register_new_matrix_user on PATH for out-of-band account creation (the
  # package is in the closure anyway — this just links its bin).
  environment.systemPackages = [ config.services.matrix-synapse.package ];

  # ===========================================================================
  # Postgres — synapse + bridges ride the existing cluster (immich's). Created
  # imperatively-but-idempotently as a oneshot because ensureDatabases can't
  # set per-db collation, and synapse demands C.
  # ===========================================================================
  systemd.services.matrix-db-setup = {
    description = "Create postgres roles/databases for synapse and mautrix bridges";
    after = [ "postgresql.service" ];
    requires = [ "postgresql.service" ];
    before = [
      "matrix-synapse.service"
      "mautrix-signal.service"
    ];
    requiredBy = [
      "matrix-synapse.service"
      "mautrix-signal.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      User = "postgres";
      Group = "postgres";
    };
    path = [ config.services.postgresql.package ];
    script = ''
      ensure_role_and_db() {
        local name="$1"
        psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='$name'" | grep -q 1 \
          || psql -c "CREATE ROLE \"$name\" LOGIN"
        psql -tAc "SELECT 1 FROM pg_database WHERE datname='$name'" | grep -q 1 \
          || createdb --owner="$name" --template=template0 --encoding=UTF8 \
               --lc-collate=C --lc-ctype=C "$name"
      }
      ensure_role_and_db matrix-synapse
      ensure_role_and_db mautrix-signal
    '';
  };

  # ===========================================================================
  # mautrix-signal — Signal as a linked device. No secrets needed here: the
  # module generates the appservice registration + tokens in
  # /var/lib/mautrix-signal on first start and registers it with synapse.
  # Login (after deploy): DM @signalbot:intentiondense.net → `login qr` →
  # scan from Signal app (Settings → Linked Devices).
  # ===========================================================================
  services.mautrix-signal = {
    enable = true;
    registerToSynapse = true; # default, but explicit
    # Contains MAUTRIX_SIGNAL_PICKLE_KEY — substituted into the config by the
    # module's envsubst preStart. Static so the bridge's crypto pickle survives
    # restarts (the upstream "generate" default would brick it every boot).
    environmentFile = config.sops.secrets.mautrix_signal_env.path;
    settings = {
      homeserver.address = "http://127.0.0.1:8008";
      appservice.hostname = "127.0.0.1"; # module default binds [::]; loopback is all we need
      database = {
        type = "postgres";
        uri = "postgresql:///mautrix-signal?host=/run/postgresql";
      };
      bridge = {
        # Everyone on this (single-person, registration-closed) homeserver is a
        # bridge admin — sidesteps hardcoding the MXID before the account exists.
        permissions."intentiondense.net" = "admin";
        relay.enabled = false; # module default enables relay mode; nobody here needs it
      };
      backfill.enabled = true;
      provisioning.shared_secret = "disable"; # no external provisioning API consumers
      # E2EE *support* (not default): Element X can only create encrypted rooms,
      # so the management room with @signalbot must be readable encrypted. But
      # default=false keeps PORTALS unencrypted — plaintext-on-our-server-only,
      # which is what keeps the watch client simple. Flip default→true if the
      # watch's E2EE ever proves solid end-to-end.
      encryption = {
        allow = true;
        default = false;
        require = false;
        pickle_key = "$MAUTRIX_SIGNAL_PICKLE_KEY"; # from environmentFile via envsubst
      };
    };
  };

  # ===========================================================================
  # nginx + ACME — TLS termination on the public NIC.
  # ===========================================================================
  security.acme = {
    acceptTerms = true;
    defaults.email = "sylvestris.h@proton.me";
  };

  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    recommendedOptimisation = true;
    recommendedGzipSettings = true;

    # Bare-IP / wrong-SNI scanners get a dropped TLS handshake, not a cert
    # that leaks the domain (CT logs leak it anyway, but no free lunches).
    virtualHosts."reject-default" = {
      serverName = "_";
      default = true;
      rejectSSL = true;
      locations."/".return = "444";
    };

    virtualHosts."intentiondense.net" = {
      forceSSL = true;
      enableACME = true; # http-01 via the port-80 listener

      locations."/_matrix" = {
        proxyPass = "http://127.0.0.1:8008";
        extraConfig = ''
          client_max_body_size 100M;
          proxy_read_timeout 90s;
        '';
      };
      locations."/_synapse/client" = {
        proxyPass = "http://127.0.0.1:8008";
      };

      # Client-side discovery: lets clients find the homeserver from the bare
      # domain. NO /.well-known/matrix/server — that's federation, which is off.
      locations."= /.well-known/matrix/client" = {
        return = ''200 '{"m.homeserver":{"base_url":"https://intentiondense.net"}}' '';
        extraConfig = ''
          default_type application/json;
          add_header Access-Control-Allow-Origin *;
        '';
      };

      # Nothing else lives on the apex (yet).
      locations."/".return = "404";
    };
  };

  # The tailnet-only exception — see header. 80 is http-01 + redirect only.
  networking.firewall.allowedTCPPorts = [
    80
    443
  ];
}
