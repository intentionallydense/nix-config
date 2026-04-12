# Hermes Agent — Deployment Guide

Read-only personal assistant. Runs in a hardened rootless-style podman container
with egress filtered to the specific API endpoints it needs.

---

## What this module does

- Pulls `ghcr.io/nousresearch/hermes-agent:v2026.4.8` (pinned)
- Mounts `/var/lib/hermes` as the persistent data volume (`/opt/data` in container)
- Injects API keys from sops-managed secrets as an env file
- Creates a dedicated podman bridge network (`hermes-net`, `172.28.0.0/28`)
- Loads an `inet hermes` nftables table that default-drops all container egress
  except DNS (1.1.1.1), NTP (162.159.200.1), and resolved IPs for:
  - `api.deepseek.com`
  - `api.telegram.org`
  - `api.tavily.com`

---

## Prerequisites

- sops-nix is already wired in your flake (it is on carbon)
- Your age key is at `~/.ssh/id_ed25519` (already configured)
- Podman is available (this module enables `virtualisation.podman`)

---

## Step 1 — Add secrets to secrets.yaml

Run from `~/NixOS/secrets/`:

```bash
cd ~/NixOS/secrets
sops secrets.yaml
```

Add these three keys alongside your existing secrets:

```yaml
hermes_deepseek_key: <your DeepSeek API key from platform.deepseek.com>
hermes_telegram_token: <your Telegram bot token from @BotFather>
hermes_tavily_key: <your Tavily API key from app.tavily.com>
```

sops will encrypt them on save. Commit the updated `secrets.yaml`.

---

## Step 2 — Add the module to configuration.nix

In `hosts/carbon/configuration.nix`, add to the `imports` list:

```nix
../../modules/server/hermes
```

Then configure it (in the same file or a dedicated block):

```nix
services.hermes = {
  enable = true;
  telegramChatId = 123456789;  # your Telegram chat ID (@userinfobot)

  # Directories Hermes can read (read-only bind mounts into the container)
  readOnlyMounts = [
    { source = "/home/fluoride/Documents"; dest = "/mnt/docs"; }
    { source = "/home/fluoride/projects";  dest = "/mnt/projects"; }
  ];
};
```

Also add the new sops secrets to the host's sops block:

```nix
sops.secrets.hermes_deepseek_key = {};
sops.secrets.hermes_telegram_token = {};
sops.secrets.hermes_tavily_key = {};
```

---

## Step 3 — Deploy

```bash
sudo nixos-rebuild switch --flake .#carbon
```

This will:
1. Create the `hermes` system user (UID 10000) and `/var/lib/hermes`
2. Activate sops secrets and render `/run/secrets-rendered/hermes.env`
3. Start `hermes-network-setup`, `hermes-nft-setup`, `hermes-resolve-egress`
   in order, then start the container

---

## Verify it's running

```bash
# Container status
sudo podman ps

# Container logs (live)
sudo podman logs -f hermes

# Network egress whitelist (should show resolved IPs)
sudo nft list set inet hermes egress_whitelist

# Systemd service status
systemctl status podman-hermes hermes-nft-setup hermes-resolve-egress

# Confirm egress whitelist was populated
journalctl -u hermes-resolve-egress --no-pager
```

Expected: the egress set should contain several IPs (Telegram and DeepSeek are
both Cloudflare-fronted and resolve to multiple addresses).

---

## Refresh the egress whitelist

If API providers rotate their IPs and the container starts failing HTTPS
connections (you'll see `drop` hits in `nft list ruleset`):

```bash
sudo systemctl restart hermes-resolve-egress
```

This flushes and repopulates the set without restarting the container.

If the container is stuck mid-request, restart it too:

```bash
sudo systemctl restart podman-hermes
```

---

## Rollback

NixOS rollback works as expected:

```bash
sudo nixos-rebuild switch --rollback
```

On stop, the module's cleanup hooks:
- `hermes-nft-setup.service` ExecStop: `nft delete table inet hermes`
- `hermes-network-setup.service` ExecStop: `podman network rm -f hermes-net`

So rollback leaves no orphaned nftables rules or podman networks.

If the container image changes, you'll need to pull the old image manually or
let podman pull the pinned tag from the previous generation's image reference.

---

## Changing the LLM provider

In `default.nix`, the model config is in `hermesConfigFile`:

```nix
model = {
  default = "deepseek-chat";
  provider = "deepseek";
  base_url = "https://api.deepseek.com/v1";
};
```

To swap to a different provider, change those three lines and add the new
API endpoint to `egressDomains`. Also update the sops secret and the template
substitution in `sops.templates."hermes.env".content`.

---

## Judgment calls / known limitations

**Container start command**: The container uses the image's default entrypoint.
If Hermes doesn't start in Telegram gateway mode automatically, add to the
module config:
```nix
# In the container definition, add:
extraOptions = [ ... "--entrypoint" "hermes" ];
# and set cmd = [ "telegram" ];
```
Or check `sudo podman inspect ghcr.io/nousresearch/hermes-agent:v2026.4.8`
for the `Cmd` and `Entrypoint` values.

**IP rotation**: The egress whitelist is refreshed once at boot. If CDN IPs
rotate during uptime, connections fail until `hermes-resolve-egress` is
restarted. This is intentional (fail-loud over fail-open).

**seccomp**: Using the default podman seccomp profile. If Hermes crashes with
`EPERM` or `ENOSYS`, add `--security-opt=seccomp=unconfined` to `extraOptions`
and file a bug upstream.

**Telegram gateway only**: The HTTP API server is disabled (`api_server.enabled = false`).
To re-enable it, set that to `true` in `hermesConfigFile` and expose the port
via `ports = [ "127.0.0.1:8642:8642" ]` in the container config.
