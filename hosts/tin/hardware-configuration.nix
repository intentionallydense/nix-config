# Minimal hardware profile for tin — Hetzner Cloud VPS (x86_64, KVM/virtio).
# Hand-written (not nixos-generate-config'd) because the box is provisioned
# declaratively via nixos-anywhere. Filesystems are owned by disko (./disko.nix);
# this file carries only the virtio boot essentials.
{ lib, modulesPath, ... }:
{
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  boot.initrd.availableKernelModules = [
    "virtio_pci"
    "virtio_scsi"
    "virtio_blk"
    "sr_mod"
    "sd_mod"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ ];
  boot.extraModulePackages = [ ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
