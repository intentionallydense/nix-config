# Nightly restic backups → Backblaze B2 (off-provider on purpose: a Hetzner
# account problem must not take tin AND its backups down together).
#
# tin had NO backups before 2026-07-22 — the hc_backup_url / hc_aotd_url
# secrets were carbon-era orphans nothing referenced. This module is the real
# thing: immich originals (the irreplaceable core), full postgres dumps,
# synapse media + signing keys, navidrome/calibre state, books, and the music
# library (40 GB; re-downloadable in principle, curated pain in practice).
# The vault (~/rubidium) is deliberately absent — Obsidian Sync already
# replicates it to germanium and Obsidian's servers.
#
# Layering:
#   - services.postgresqlBackup dumps the whole cluster at 03:15 (backupAll:
#     immich, matrix-synapse, the mautrix bridge DBs, and whatever gets added
#     later — file-level copies of a live postgres are not restorable, dumps
#     are). Dumps land in /var/backup/postgresql, which restic then ships.
#   - services.restic.backups.tin runs at 04:00 (dumps are done by then),
#     prunes to 7 daily / 4 weekly / 6 monthly, and checks repo integrity.
#   - healthchecks.io check `restic-backup` (period 24 h, grace 6 h, ntfy):
#     /start when the run begins, success on completion, /fail on failure —
#     and grace expiry catches the run silently never starting at all.
#
# Secrets (sops): b2_key_id + b2_application_key (composed into an env file),
# restic_repository ("b2:<bucket>:" — kept out of the public repo), and
# restic_password. Recovery story: encrypted secrets.yaml lives in the public
# git repo and germanium's age key (bromide_germanium) is a recipient, so a
# dead tin does not orphan the repository password. RESTORE-TEST BEFORE TRUST.
# Used by: tin.
{ pkgs, config, ... }:
let
  hcPing = mode: pkgs.writeShellScript "restic-hc-ping${mode}" ''
    curl -fsS -m 10 "$(cat ${config.sops.secrets.hc_restic_url.path})${mode}" >/dev/null || true
  '';
in
{
  sops.secrets = {
    b2_key_id = { };
    b2_application_key = { };
    restic_repository = { };
    restic_password = { };
    hc_restic_url = { };
  };

  sops.templates."restic-env".content = ''
    B2_ACCOUNT_ID=${config.sops.placeholder.b2_key_id}
    B2_ACCOUNT_KEY=${config.sops.placeholder.b2_application_key}
  '';

  # Full-cluster dumps; restic ships /var/backup/postgresql below.
  services.postgresqlBackup = {
    enable = true;
    backupAll = true;
    startAt = "*-*-* 03:15:00";
    location = "/var/backup/postgresql";
  };

  services.restic.backups.tin = {
    repositoryFile = config.sops.secrets.restic_repository.path;
    passwordFile = config.sops.secrets.restic_password.path;
    environmentFile = config.sops.templates."restic-env".path;
    initialize = true; # first run creates the repo

    paths = [
      "/var/lib/immich"
      "/var/backup/postgresql"
      "/var/lib/matrix-synapse"
      "/var/lib/navidrome"
      "/var/lib/calibre-web"
      "/srv/media/books"
      "/srv/media/music"
    ];
    exclude = [
      # Regenerable immich derivatives — originals + DB are what matter.
      "/var/lib/immich/thumbs"
      "/var/lib/immich/encoded-video"
    ];

    pruneOpts = [
      "--keep-daily 7"
      "--keep-weekly 4"
      "--keep-monthly 6"
    ];
    # Cheap metadata check each run; read-data sampling would burn B2 egress.
    runCheck = true;

    timerConfig = {
      OnCalendar = "*-*-* 04:00:00";
      RandomizedDelaySec = "30min";
      Persistent = true; # a nightly missed while tin was down should run at boot
    };
  };

  # healthchecks pings around the run. ExecStartPre/Post only fire on the
  # success path for oneshots; OnFailure covers the rest.
  systemd.services."restic-backups-tin" = {
    path = [ pkgs.curl ];
    serviceConfig = {
      ExecStartPre = [ "${hcPing "/start"}" ];
      ExecStartPost = [ "${hcPing ""}" ];
    };
    unitConfig.OnFailure = [ "restic-backup-failed-ping.service" ];
  };

  systemd.services.restic-backup-failed-ping = {
    description = "Signal backup failure to healthchecks.io";
    path = [ pkgs.curl ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${hcPing "/fail"}";
    };
  };
}
