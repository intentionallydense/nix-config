# nix-config

NixOS flake for **tin** — a Hetzner Cloud VPS (x86_64-linux) serving a personal
media/photo/matrix stack, reachable tailnet-only.

This repo used to manage a multi-host fleet (carbon, silicon, germanium); that
layout is preserved at the [`fleet-final`](../../tree/fleet-final) tag. Naming
follows the periodic table: hosts are group 14, usernames are group 17 halides.

## What runs here

- **Immich** — photo library (inlined in `configuration.nix`)
- **Navidrome / slskd / music-shelf** — music streaming, Soulseek (egress via
  Mullvad wireproxy), search UI (`modules/music`, `modules/mullvad-egress`)
- **Calibre-Web** — books (`modules/books`)
- **Synapse + mautrix-signal** — Matrix homeserver + Signal bridge; the one
  service exposed on the public NIC, 80/443 (`modules/matrix`)
- **Prometheus + Grafana** — monitoring (`modules/monitoring`)
- **Headless Obsidian** — vault Sync replica on Xvfb (`modules/obsidian-vault`)

## Structure

```
flake.nix                    Inputs: nixpkgs, sops-nix, disko
configuration.nix            Host config (lean headless base; no home-manager)
hardware-configuration.nix   Hetzner KVM/virtio
disko.nix                    Disk layout (applied by nixos-anywhere at install)
fish.nix                     Interactive shell, system-level
modules/                     One directory per service (+ nix-ld)
scripts/                     Auxiliary scripts (vast.ai onstart)
secrets/secrets.yaml         sops-encrypted (age); .sops.yaml has recipients
docs/                        tin migration notes
```

## Deploying

Built on tin itself:

```
sudo nixos-rebuild switch --flake .#tin
```

Secrets decrypt at activation via the host SSH key
(`/etc/ssh/ssh_host_ed25519_key` → age). On-box editing works with a user age
key in `~/.config/sops/age/keys.txt` (`sops secrets/secrets.yaml`).
