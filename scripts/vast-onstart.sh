#!/usr/bin/env bash
# vast-onstart.sh — Vast.ai onstart script: join the tailnet + prep for research.
#
# Set these in the Vast template's Environment (NOT in this file — this repo is public):
#   TS_AUTHKEY   tailscale auth key — make it Ephemeral + Reusable, tagged (e.g. tag:vast),
#                from https://login.tailscale.com/admin/settings/keys
#   TS_HOSTNAME  optional, defaults to vast-gpu
#
# Vast containers usually lack a TUN device, so tailscaled runs in userspace-networking
# mode: outbound tailnet dials need the SOCKS5 proxy (localhost:1055), but INBOUND
# connections (ssh from laptop/tin to this box) work transparently — which is the
# direction we care about.
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# --- tailscale (userspace mode; no TUN needed) ---
if ! command -v tailscale >/dev/null 2>&1; then
  curl -fsSL https://tailscale.com/install.sh | sh
fi
mkdir -p /var/lib/tailscale
nohup tailscaled \
  --tun=userspace-networking \
  --socks5-server=localhost:1055 \
  --state=/var/lib/tailscale/tailscaled.state \
  >/var/log/tailscaled.log 2>&1 &
sleep 2
tailscale up --authkey="${TS_AUTHKEY}" --hostname="${TS_HOSTNAME:-vast-gpu}" --ssh
echo "tailnet: $(tailscale ip -4 2>/dev/null || echo pending)"

# --- research prep ---
# Persist HF_TOKEN for ssh sessions: docker env reaches PID 1, but sshd spawns
# clean login environments; pam_env re-injects anything in /etc/environment.
[ -n "${HF_TOKEN:-}" ] && echo "HF_TOKEN=${HF_TOKEN}" >> /etc/environment
command -v uv >/dev/null 2>&1 || curl -LsSf https://astral.sh/uv/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"

# Clone via https + GITHUB_TOKEN env if the repo is private and no key is present:
#   git clone https://x-access-token:${GITHUB_TOKEN}@github.com/intentionallydense/metagaming.git
# (or add a fine-grained deploy key to the repo and ssh-clone)

# Typical serving session (run via ssh once you're in, not here):
#   uvx --from vllm vllm serve allenai/Olmo-3-7B-Think --port 8080
# then on tin:  uv run run_eval.py --base-url http://<this-box-tailnet-ip>:8080/v1 ...

echo "onstart complete"
