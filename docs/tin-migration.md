# Migration: carbon (home-server laptop) → tin (Hetzner Cloud VPS)

Goal: move carbon's always-on serving stack to a Hetzner box so the Dell Latitude
becomes a normal laptop again. **Phase 1 = serving daemons only.** The
scheduled/automation layer (briefing, AOTD, overnight-research, publish-blog) and
anything vault/claude-coupled is **deliberately NOT ported** — Sylvia wants to
redo that cleanly, not straight-port it.

## STATUS — Phase 1 serving stack is LIVE (installed 2026-06-12, ~00:0x BST)

**Box:** Hetzner VPS, **x86_64** (ARM CAX was out of stock), 8 vCPU / 16 GB / 305 GB.
- Public IPv4: **46.224.106.224**  ·  Tailnet: **tin = 100.65.236.26**
- Naming: host **tin**, user **iodide** (period-5 halide), SSH alias *antimony* (not yet added to common.nix).

**All services active, 0 failed units, all reachable over the tailnet:**

| Service | Port | Tailnet check |
|---|---|---|
| Jellyfin | 8096 | 302 ✓ |
| Immich | 2283 | 200 ✓ |
| Navidrome | 4533 | 302 ✓ |
| slskd | 5030 | 200 ✓ |
| music-shelf | 4534 | 200 ✓ |
| Calibre-Web | 8084 | 302 ✓ |
| Grafana | 3000 | 200 ✓ |
| Prometheus | 9090 | 302 ✓ |
| OwnTracks | 8083 | 200 ✓ |

## What was done tonight (autonomous)
- `nixos-anywhere` install onto the box (disko: 1G ESP / 8G swap / ext4 root on /dev/sda).
- **Invidious dropped** from the build — its module fetches a *live* GitHub draft-PR
  patch (iv-org/invidious#5736) whose hash drifted upstream and broke the build.
- **sops re-key:** tin's host age key (`age1um7zmrhwyfukppwvj079ur2nqjxlmcm94slzjs2jaa5jc3na2pgskqh3vs`)
  added to `.sops.yaml`, blind `sops updatekeys`. secrets/secrets.yaml re-encrypted to all 3 hosts.
- **Tailnet joined** (`tailscale up --ssh`, the auth key Sylvia provided).
- **root kept on bash** (was caught by `defaultUserShell = fish`, which breaks remote nixos-rebuild).
- **book_library + music-shelf app transferred**; **music library (34 GB) rsyncing in background**.

### ⚠ Manual/imperative bits applied on the box (NOT yet declarative — cleanup target)
- POSIX ACL traversal on `/home/iodide` for navidrome/slskd/calibre-web:
  `setfacl -m u:navidrome:--x -m u:slskd:--x -m u:calibre-web:--x /home/iodide`
  (carbon does this imperatively too — nowhere in the flake. Make it tmpfiles `A+`.)
- `music_library/{library,incoming/.incomplete}` created, `chown -R iodide:media`, `chmod 2775`.

## YOUR TO-DO (when you're up)
1. **Delete the Tailscale auth key** from the admin console (it was pasted in chat → logs).
2. **Lock down public SSH** — remove `networking.firewall.allowedTCPPorts = [ 22 ];` from
   `hosts/tin/configuration.nix` and rebuild. Verified safe: tailnet SSH + all services
   work over 100.65.236.26. After this, tin is tailnet-only like carbon.
3. **Point your apps** at `tin`/`100.65.236.26`: Amperfy/Symfonium→4533, Jellyfin→8096,
   Immich→2283, OwnTracks→8083, KOReader OPDS→`http://100.65.236.26:8084/opds`, Grafana→3000.
4. **Review + commit the `tin` branch** (left uncommitted; includes the .sops.yaml /
   secrets.yaml re-key). carbon is untouched.

## Deferred / cleanup (your "this is weird, I'll clean it up" list)
- **Invidious** — revisit the patch overlay (pin a real commit, not the live PR); reconsider running it on a DC IP.
- **Make the ACL traversal declarative** (tmpfiles `A+` on /home), on both tin and carbon.
- **Scheduled/vault/claude layer** (briefing, AOTD, overnight-research, publish) — clean redo, Phase 2.
- **Backups** — retarget the `backup` module off the external SanDisk to a Hetzner Storage Box / restic.
- **slskd → Mullvad** — port the wireproxy module from the `silicon-nixos` branch; until then slskd is on the raw IP.

## carbon teardown (the cutover — your call, when ready)
Drop the `modules/server/*` imports + `modules/server/power` from `hosts/carbon/configuration.nix`,
re-enable suspend, remove the 80% charge cap and forced fan. Rebuild → it's a laptop again.

## Masked on tin (ride in via shared modules; intentionally off)
aotd-play/-download (BT speaker + briefing), kobo-briefing (briefing), music-auto-import,
owntracks-day, carbon-alert-check (scheduled). mp3-sync/kobo-sync are udev-only (self-gate).
