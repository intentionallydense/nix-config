# Handoff: give germanium its own sops identity (wireproxy secrets)

**Status: ✅ COMPLETED 2026-06-04 — see "Outcome" at bottom. (Originally a security/consistency cleanup, not a repair.)**
germanium's Mullvad/wireproxy works today. The problem is *how* it decrypts.

## The finding (verified 2026-06-04, carbon sweep)
- `.sops.yaml` recipients are only `chloride_silicon` (`age16t99…`) and `fluoride_carbon` (`age17chs…`).
- `secrets/secrets.yaml` is encrypted to exactly those two (read via cleartext recipient metadata — never decrypted).
- germanium's `~/.config/sops/age/keys.txt` resolves (via `age-keygen -y`) to **`age16t99…`** — i.e. it holds a **copy of silicon's age private key**. germanium is not a recipient in its own right; it decrypts by impersonating silicon.
- germanium's *own* ssh-derived recipient (what it SHOULD use) = `age15zk95vyfa7wrgqvx6egxc88a66f7tk5m86u864k9le9wgrhxu9ds825x6u` (`ssh-to-age < ~/.ssh/id_ed25519.pub`).
- germanium's wireproxy module (`modules/darwin/wireproxy/default.nix`) is already sops-based and correct: a launchd launcher reads `${config.sops.defaultSymlinkPath}/wireproxy/<name>` and renders the `.conf` at login. Secret keys in the file: `wireproxy/{personal,sensitive,academic,social}`.

## Why fix it
One shared age private key means compromising germanium exposes silicon's decryption identity (and vice-versa), and neither host can be revoked without re-keying the other. carbon and silicon already each use their *own* key — germanium is the odd one out.

## Migration steps (run on carbon as fluoride; that key is a current recipient)
1. **Add germanium to `.sops.yaml`:**
   ```yaml
   keys:
     - &chloride_silicon  age16t99hyvd4vazjcv53vk24hxs7kevq3r8jep38c69tu6gk65laddsfgg6d6
     - &fluoride_carbon   age17chsklmd20tfpmc9enx3hws4eed0tkcjy4fq5mcq8w9ggd8kh9lsz254m9
     - &bromide_germanium age15zk95vyfa7wrgqvx6egxc88a66f7tk5m86u864k9le9wgrhxu9ds825x6u
   creation_rules:
     - path_regex: secrets/.*\.yaml$
       key_groups:
         - age:
             - *chloride_silicon
             - *fluoride_carbon
             - *bromide_germanium
   ```
2. **Re-key the secret (blind, no plaintext exposure):**
   ```
   cd ~/NixOS
   cp secrets/secrets.yaml secrets/secrets.yaml.bak     # backup first
   sops updatekeys secrets/secrets.yaml                 # re-encrypts data key to the new recipient set
   ```
3. **Replace germanium's shared key with its own** (on germanium; back up first):
   ```
   cp ~/.config/sops/age/keys.txt ~/.config/sops/age/keys.txt.bak
   ssh-to-age -private-key -i ~/.ssh/id_ed25519 > ~/.config/sops/age/keys.txt
   ```
   Safe because step 2 made `age15zk…` a recipient, so germanium's own key can now decrypt.
4. **Verify on germanium:** re-run activation (`darwin-rebuild switch --flake ~/nix-config#germanium`, or relog), then confirm `~/.config/sops-nix/secrets/wireproxy/*` repopulate and the four `wireproxy-*` launchd agents are up:
   `launchctl print gui/$(id -u)/org.nix-community.home.wireproxy-personal | grep -E 'state|last exit'`
5. **Commit** `.sops.yaml` + re-keyed `secrets/secrets.yaml` on `main`.
   ⚠️ These files also exist on the `silicon-nixos` branch — the re-keyed secret + `.sops.yaml` must land there too (cherry-pick, or fold into the silicon-nixos→main merge), or silicon ends up on a stale recipient set.

## Guardrails (Sylvia's standing rules)
- NEVER `sops -d | grep/head`. Only blind manipulation: `sops updatekeys` / `--extract` / `--set` / `--unset`. Verify with cleartext recipient metadata or `age-keygen -y`, never by decrypting values.
- Back up `secrets/secrets.yaml` and germanium's `keys.txt` before touching either.

## Optional parity nit (skip unless you care)
germanium renders `~/.config/wireproxy/*.conf` (mode 600, contains the privkey) at login; silicon's NixOS module writes to a unit `RuntimeDirectory` (tmpfs, ephemeral). launchd has no RuntimeDirectory equivalent, so the macOS approach is the reasonable analogue — not worth changing.

---

## ✅ Outcome — completed 2026-06-04 (mgcode session, with Sylvia)

Done and verified. germanium decrypts its wireproxy secrets with its **own** ssh-derived age identity (`age15zk95…`); silicon's key copy was removed from germanium.

**Actual sequence (differs from the plan above — see gotchas):**
1. carbon: add `bromide_germanium` to `.sops.yaml` + `sops updatekeys` → commit `fc3e223`, push `main`.
2. germanium: `git pull` so the re-keyed `secrets.yaml` is in the working tree *before* the rebuild.
3. germanium: `sudo darwin-rebuild switch --flake ~/nix-config#germanium` (deploys the new secret).
4. germanium: swap `keys.txt` to its own key; kickstart `org.nix-community.home.sops-nix` → `exit 0` against the deployed secret; delete `keys.txt.bak`.
5. carbon: retire the now-orphaned old key `age16t99…` from main → commit `dee264b`, push. main's secret = carbon + germanium only.

**Gotchas (corrections to the plan above):**
- **Order is rebuild → swap, not swap → rebuild.** sops-nix decrypts the `secrets.yaml` baked into the *deployed generation* (`/nix/store/…`), not the working tree. Swapping germanium's key before the rebuild strands it (it can't decrypt the still-deployed old secret → `0 successful groups`). Get the re-keyed secret into the tree, rebuild, *then* swap.
- **`silicon-nixos` was NOT cherry-picked.** The branches diverge on `chloride_silicon` (main = old macOS key `age16t99…`; `silicon-nixos` = current NixOS key `age1v29h…`). Cherry-picking `fc3e223` would overwrite silicon's real key and lock it out. `silicon-nixos` already had the right recipients, so it was left untouched.
- germanium has no passwordless sudo, so the rebuild step needs Sylvia at the keyboard.
