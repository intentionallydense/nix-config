# Disk layout for tin (Hetzner Cloud VPS, x86_64). Applied declaratively by
# nixos-anywhere at install time, so the box is reproducible from scratch.
#
# Hetzner Cloud presents the primary virtio disk as /dev/sda. Confirm at install
# (nixos-anywhere prints the detected disk); adjust `device` if it differs.
{
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/sda";
    content = {
      type = "gpt";
      partitions = {
        ESP = {
          priority = 1;
          type = "EF00";
          size = "1G";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot";
            mountOptions = [ "umask=0077" ];
          };
        };
        swap = {
          # 8G backstop for Immich ML memory spikes (the job that caused
          # pressure on carbon's 16GB). Real partition, not just zram.
          size = "8G";
          content = {
            type = "swap";
            discardPolicy = "both";
          };
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };
}
