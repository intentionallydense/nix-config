# Launch Claude Code pointing at the Kimi For Coding subscription API via local proxy.
#
# The proxy (user-level service kimi-claude-proxy, defined in nix-config at
# modules/programs/kimi-claude-proxy/) bridges two gaps in Moonshot's Claude-Code
# support: it fakes the missing GET /v1/models/{id} endpoint and transparently
# refreshes the 15-min OAuth access_token using the refresh_token in
# ~/.kimi/credentials/kimi-code.json.
#
# Auth: uses OAuth credentials in ~/.kimi/credentials/kimi-code.json. The proxy
# refreshes the access_token as needed; as long as the refresh_token remains
# valid, nothing else is needed. If refresh ever fails (unlikely; refresh tokens
# are long-lived), reinstall kimi-cli temporarily (`nix profile install
# github:MoonshotAI/kimi-cli`) and run `/login` to get fresh credentials, then
# remove kimi-cli again.
# Moonshot explicitly supports Claude Code as a client — TOS-compliant.
#
# Usage: mgkimi [claude args]
function mgkimi
    set -l cred_file "$HOME/.kimi/credentials/kimi-code.json"
    set -l port 8787
    if not test -f $cred_file
        echo "mgkimi: kimi-code not authenticated. Run `kimi` and use `/login` first." >&2
        return 1
    end
    if not nc -z 127.0.0.1 $port 2>/dev/null
        echo "mgkimi: proxy not listening on :$port." >&2
        if test (uname) = Darwin
            echo "        (try: launchctl kickstart -k gui/(id -u)/org.nixos.kimi-claude-proxy)" >&2
        else
            echo "        (try: systemctl --user restart kimi-claude-proxy)" >&2
        end
        return 1
    end
    set -l base_url http://127.0.0.1:$port
    set -l env_prefix "env CLAUDE_CODE_NO_FLICKER=1 ANTHROPIC_BASE_URL=$base_url ANTHROPIC_AUTH_TOKEN=unused ANTHROPIC_MODEL=kimi-for-coding ANTHROPIC_SMALL_FAST_MODEL=kimi-for-coding"
    set -l work_dir $OBSIDIAN_VAULT
    if test -z "$work_dir"
        set work_dir $HOME
    end
    if test -n "$TMUX"
        cd $work_dir
        CLAUDE_CODE_NO_FLICKER=1 ANTHROPIC_BASE_URL=$base_url ANTHROPIC_AUTH_TOKEN=unused ANTHROPIC_MODEL=kimi-for-coding ANTHROPIC_SMALL_FAST_MODEL=kimi-for-coding claude $argv
    else if tmux has-session -t mg 2>/dev/null
        tmux new-window -t mg -c $work_dir \
            "$env_prefix claude $argv; exec fish"
        tmux attach-session -t mg
    else
        tmux new-session -s mg -c $work_dir \
            "$env_prefix claude $argv; exec fish"
    end
end
