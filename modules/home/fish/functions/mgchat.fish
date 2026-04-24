# Launch Claude Code from the Obsidian vault with chat-mode-prompt.md, inside the shared 'mg' tmux session.
# Replaces the default Claude Code system prompt with $OBSIDIAN_VAULT/claude/chat-mode-prompt.md.
# Permission mode comes from ~/.claude/settings.json (bypassPermissions).
# Attaches to existing 'mg' session if one is running; creates a new one otherwise.
# Usage: mgchat [claude args]
function mgchat
    set -l work_dir $OBSIDIAN_VAULT
    if test -z "$work_dir"
        echo "mgchat: OBSIDIAN_VAULT not set." >&2
        return 1
    end
    set -l prompt_file "$work_dir/claude/chat-mode-prompt.md"
    if not test -f $prompt_file
        echo "mgchat: prompt file not found at $prompt_file" >&2
        return 1
    end
    if test -n "$TMUX"
        cd $work_dir
        CLAUDE_CODE_NO_FLICKER=1 claude --system-prompt-file $prompt_file $argv
    else if tmux has-session -t mg 2>/dev/null
        tmux new-window -t mg -c $work_dir \
            "env CLAUDE_CODE_NO_FLICKER=1 claude --system-prompt-file $prompt_file $argv; exec fish"
        tmux attach-session -t mg
    else
        tmux new-session -s mg -c $work_dir \
            "env CLAUDE_CODE_NO_FLICKER=1 claude --system-prompt-file $prompt_file $argv; exec fish"
    end
end
