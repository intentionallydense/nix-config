# Automated backups to external SanDisk 2TB drive.
# Weekly snapshots (keep 4) + monthly snapshots (keep 12) using rsync --link-dest
# for space-efficient incremental backups. Backs up /home/fluoride + service state.
# Used by: carbon.
{ pkgs, username, ... }:
let
  backupMount = "/mnt/backups";
  backupScript = pkgs.writeShellScript "system-backup" ''
    set -euo pipefail

    BACKUP_ROOT="${backupMount}"
    TYPE="$1"  # "weekly" or "monthly"
    KEEP="$2"  # how many snapshots to retain

    # Bail if the drive isn't mounted
    if ! mountpoint -q "$BACKUP_ROOT"; then
      echo "ERROR: $BACKUP_ROOT is not mounted, skipping backup"
      exit 1
    fi

    DEST_DIR="$BACKUP_ROOT/$TYPE"
    TIMESTAMP=$(date +%Y-%m-%d_%H-%M-%S)
    SNAPSHOT="$DEST_DIR/$TIMESTAMP"

    mkdir -p "$DEST_DIR"

    # Find the most recent snapshot for --link-dest (hard link unchanged files)
    LATEST=$(ls -1d "$DEST_DIR"/????-??-??_* 2>/dev/null | tail -1 || true)
    LINK_DEST_ARG=""
    if [ -n "$LATEST" ]; then
      LINK_DEST_ARG="--link-dest=$LATEST"
    fi

    # rsync home directory + service state
    ${pkgs.rsync}/bin/rsync -a --delete \
      $LINK_DEST_ARG \
      --exclude='.cache' \
      --exclude='.local/share/Trash' \
      --exclude='music_library/incoming/.incomplete' \
      --exclude='miniconda3' \
      --exclude='.nix-defexpr' \
      --exclude='.nix-profile' \
      --exclude='.local/state/nix' \
      /home/${username}/ \
      "$SNAPSHOT/home/"

    # Back up service state directories (immich, grafana, owntracks, navidrome, syncthing)
    for svc in immich grafana owntracks navidrome syncthing; do
      SVC_DIR="/var/lib/$svc"
      if [ -d "$SVC_DIR" ]; then
        ${pkgs.rsync}/bin/rsync -a --delete \
          $LINK_DEST_ARG \
          "$SVC_DIR/" \
          "$SNAPSHOT/var-lib/$svc/"
      fi
    done

    echo "Backup complete: $SNAPSHOT"

    # Prune old snapshots, keep $KEEP most recent
    SNAPSHOTS=$(ls -1d "$DEST_DIR"/????-??-??_* 2>/dev/null | sort)
    COUNT=$(echo "$SNAPSHOTS" | wc -l)
    if [ "$COUNT" -gt "$KEEP" ]; then
      REMOVE_COUNT=$((COUNT - KEEP))
      echo "$SNAPSHOTS" | head -n "$REMOVE_COUNT" | while read -r OLD; do
        echo "Pruning old snapshot: $OLD"
        rm -rf "$OLD"
      done
    fi
  '';
in
{
  # Mount the backup drive by UUID — nofail so the system boots even if unplugged
  fileSystems."${backupMount}" = {
    device = "/dev/disk/by-uuid/c8a33cc9-9485-4c24-b88a-f1638abba849";
    fsType = "ext4";
    options = [
      "nofail"
      "x-systemd.mount-timeout=5"
      "noatime"
    ];
  };

  # --- Weekly backup: runs Sunday 3am, keeps 4 snapshots ---
  systemd.services.backup-weekly = {
    description = "Weekly rsync backup to external drive";
    after = [ "mnt-backups.mount" ];
    requires = [ "mnt-backups.mount" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${backupScript} weekly 4";
      # Needs root to read /var/lib service dirs
      TimeoutStartSec = "4h";
    };
  };
  systemd.timers.backup-weekly = {
    description = "Run weekly backup every Sunday at 3am";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sun *-*-* 03:00:00";
      Persistent = true;
    };
  };

  # --- Monthly backup: runs 1st of month 4am, keeps 12 snapshots ---
  systemd.services.backup-monthly = {
    description = "Monthly rsync backup to external drive";
    after = [ "mnt-backups.mount" "backup-weekly.service" ];
    requires = [ "mnt-backups.mount" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${backupScript} monthly 12";
      TimeoutStartSec = "4h";
    };
  };
  systemd.timers.backup-monthly = {
    description = "Run monthly backup on the 1st at 4am";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-01 04:00:00";
      Persistent = true;
    };
  };

  environment.systemPackages = [ pkgs.rsync ];
}
