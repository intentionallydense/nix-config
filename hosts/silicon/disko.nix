# Declarative full-disk layout for silicon (2019 16" MacBook Pro, MacBookPro16,1).
# FULL WIPE — this erases macOS. Applied by disko via nixos-anywhere / disko-install.
#
# ⚠️ device MUST be confirmed on silicon before running (lsblk). The 16"'s internal
#    SSD is behind the T2 but enumerates as a normal NVMe — almost certainly nvme0n1.
{ ... }:
{
  disko.devices.disk.main = {
    device = "/dev/nvme0n1";
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          size = "1G";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        swap = {
          size = "8G";
          content = {
            type = "swap";
            # No resumeDevice: hibernate on T2 Macs is unreliable; this is plain swap.
          };
        };
        root = {
          size = "100%";
          content = {
            type = "btrfs";
            extraArgs = [ "-f" ];
            # Subvolumes give cheap snapshots/rollback — the safety net for an experiment box.
            subvolumes = {
              "@" = {
                mountpoint = "/";
                mountOptions = [ "compress=zstd" "noatime" ];
              };
              "@home" = {
                mountpoint = "/home";
                mountOptions = [ "compress=zstd" "noatime" ];
              };
              "@nix" = {
                mountpoint = "/nix";
                mountOptions = [ "compress=zstd" "noatime" ];
              };
            };
          };
        };
      };
    };
  };
}
