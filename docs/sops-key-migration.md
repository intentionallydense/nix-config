# SOPS key migration — admin key + per-host scoping

**Status:** drafted 2026-06-03 — *NOT yet executed*. This is a reference plan to
run later (ideally when folding `silicon-nixos` back into `main`).

## Why this exists

The `silicon-nixos` branch re-keyed `secrets/secrets.yaml`: converting the Intel
Mac to NixOS generated a **new** age key, and the re-key repointed the
`chloride_silicon` anchor to it (`age1v29h74…`) **and dropped the old key**
(`age16t99…`) — which is the admin key on germanium (`~/.config/sops/age/keys.txt`).
Result: germanium (and even fluoride's user key) can no longer decrypt the branch
secrets. Anchors now mean different keys on different branches.

**Goal:** one *admin* key that is a recipient of **every** secret (so the laptop
can always edit/decrypt and you can never lock yourself out), plus one *runtime*
key per host scoped to only the secrets that host needs. This is NOT "one private
key copied to every host" — that would defeat blast-radius isolation (a carbon
compromise must not expose the Macs' Mullvad/wireproxy keys) and reintroduce a
key-distribution problem.

## The real keys (public — safe to commit)

| name | age public key | what it is / where the private half lives |
|------|----------------|-------------------------------------------|
| **admin**   | `age16t99hyvd4vazjcv53vk24hxs7kevq3r8jep38c69tu6gk65laddsfgg6d6` | master/editing key = germanium `~/.config/sops/age/keys.txt` (historically the old Intel-Mac "chloride_silicon" key, reused) |
| **carbon**  | `age17chsklmd20tfpmc9enx3hws4eed0tkcjy4fq5mcq8w9ggd8kh9lsz254m9` | carbon's fluoride **user** key (`/home/fluoride/.ssh/id_ed25519` → age) |
| **silicon** | `age1v29h74cxyhy3u5uknccg894cdsn3f8sfftfhu9mtr3h3aefy5fqs7k3aev` | the new NixOS silicon's key (currently the branch's `chloride_silicon`) |
| *(germanium, optional)* | `age15zk95vyfa7wrgqvx6egxc88a66f7tk5m86u864k9le9wgrhxu9ds825x6u` | germanium's own user key — only needed if you want germanium to run off its own key and keep admin editing-only |
| *(carbon host, optional)* | `age1a9ujhg0dwrzsfmqalnvag22vafw9cz3ehyzarvfkhlfx8yufxqlqw5etv0` | carbon's **host** key — swap to this if you prefer the idiomatic host-key (root-decrypt, survives user changes) over the user key |

Scoping (confirmed by grep): `wireproxy/*` is the only Mac-side secret set
(`modules/darwin/wireproxy`, used by germanium + silicon). Everything else is
carbon's (`modules/programs/secrets` + server modules, carbon-only). germanium
declares no non-wireproxy secrets.

## Target `.sops.yaml`

```yaml
keys:
  - &admin    age16t99hyvd4vazjcv53vk24hxs7kevq3r8jep38c69tu6gk65laddsfgg6d6  # master / editing (germanium keys.txt)
  - &carbon   age17chsklmd20tfpmc9enx3hws4eed0tkcjy4fq5mcq8w9ggd8kh9lsz254m9  # carbon (fluoride user key)
  - &silicon  age1v29h74cxyhy3u5uknccg894cdsn3f8sfftfhu9mtr3h3aefy5fqs7k3aev  # silicon (NixOS, new key)

creation_rules:
  # Carbon's server + research secrets — carbon decrypts, you edit.
  - path_regex: secrets/carbon\.ya?ml$
    key_groups: [ { age: [ *admin, *carbon ] } ]

  # Mac / Mac-NixOS wireproxy (Mullvad) — germanium decrypts via the admin key it
  # already holds; silicon via its own. Carbon is deliberately NOT a recipient.
  - path_regex: secrets/macs\.ya?ml$
    key_groups: [ { age: [ *admin, *silicon ] } ]

  # Legacy single file — keep ONLY until the split is verified, then delete.
  - path_regex: secrets/secrets\.ya?ml$
    key_groups: [ { age: [ *admin, *carbon ] } ]

  # Fail-closed default: any stray secrets file is at least editable by you.
  - path_regex: secrets/.*\.ya?ml$
    key_groups: [ { age: [ *admin ] } ]
```

## File split

| file | secrets | recipients |
|------|---------|------------|
| `secrets/macs.yaml`   | `wireproxy/{personal,academic,sensitive,social}` | `admin`, `silicon` |
| `secrets/carbon.yaml` | grafana_secret_key, navidrome_*, slskd_*, ntfy_alert_url, hc_* (backup/aotd/heartbeat/briefing), vastai/openrouter/huggingface/deepseek_hermes_*/tavily/telegram keys, ft_/acx_ session cookies | `admin`, `carbon` |

## Host config changes (after the split)

- **germanium** `home/default.nix`: `defaultSopsFile = ../secrets/macs.yaml;`
  (only uses wireproxy). Keep `age.keyFile = …/keys.txt` — admin key does
  germanium's runtime decryption *and* your editing.
- **carbon** `hosts/carbon/configuration.nix`: `defaultSopsFile = ../../secrets/carbon.yaml;`
  keep `age.sshKeyPaths = [ "/home/fluoride/.ssh/id_ed25519" ];`
- **silicon** (`hosts/silicon/nixos.nix`, on the branch): point wireproxy at
  `secrets/macs.yaml`; age key = silicon's own **user** key (wireproxy is a
  *user* systemd service → needs a user-readable key = `age1v29h74…`).

## Migration checklist

1. **Back up the admin key** (`~/.config/sops/age/keys.txt` = `age16t99…`)
   offline. It's the master — lose it and you lose edit access to everything.
2. Work on a branch off `main`; merge when done, then rebase `silicon-nixos`
   onto it (this retires the anchor drift).
3. Drop in the new `.sops.yaml` above.
4. Split — plaintext only ever in `/tmp`, under `umask 077`:
   ```sh
   umask 077
   sops -d secrets/secrets.yaml > /tmp/all.yaml
   yq '{wireproxy: .wireproxy}' /tmp/all.yaml > secrets/macs.yaml   && sops -e -i secrets/macs.yaml
   yq 'del(.wireproxy)'        /tmp/all.yaml > secrets/carbon.yaml && sops -e -i secrets/carbon.yaml
   grep -l 'sops:' secrets/macs.yaml secrets/carbon.yaml   # BOTH must show sops metadata (= encrypted)
   shred -u /tmp/all.yaml
   ```
   (no `yq`? decrypt and hand-split via two `sops <file>` editor sessions.)
5. **Test decrypt on every host BEFORE rebuilding** — load-bearing safety step:
   - germanium: `sops -d secrets/macs.yaml` **and** `secrets/carbon.yaml` → both succeed (admin).
   - carbon: `sops -d secrets/carbon.yaml` → succeeds; `secrets/macs.yaml` → **fails** (isolation working).
   - silicon: `sops -d secrets/macs.yaml` → succeeds.
6. Update the three `defaultSopsFile`s (above).
7. `nixos-rebuild build` / `darwin-rebuild build` each host (no activation) —
   confirms every `sops.secrets.*` reference resolves.
8. Rebuild for real, then verify secret-consumers came up: navidrome / grafana /
   alerts on carbon, the four wireproxy tunnels on germanium.
9. Only once all three hosts verify: delete `secrets/secrets.yaml` + its legacy rule.

## Optional polish (not required)

- Give germanium its **own** runtime key (`age15zk95…` in `macs.yaml`, point
  germanium's `sshKeyPaths` at its own key) and demote admin to editing-only.
- Generate a **fresh** admin key with `age-keygen` instead of reusing the old
  Intel-Mac silicon key (`age16t99…`); add it everywhere, then retire the old one.
- Switch carbon to its **host** key (`age1a9ujhg…`) for the idiomatic
  root-decrypt-at-activation pattern.

## Who decrypts what (target state)

| secret set | admin (germanium) | carbon | silicon |
|------------|:-:|:-:|:-:|
| `macs.yaml` (wireproxy) | ✅ | ❌ | ✅ |
| `carbon.yaml` (server/research) | ✅ | ✅ | ❌ |
