# Resume the most recent Claude Code session from the Obsidian vault in the shared 'mg' tmux session.
# Requires a mode argument so the right system prompt is re-applied — Claude Code doesn't preserve
# the original session's system prompt on resume, so the flags have to be passed again explicitly.
# chat = chat-mode-prompt.md as base. code = same base plus CODING.md appended.
# Attaches to existing 'mg' session if one is running; creates a new one otherwise.
# Usage: mgres (chat|code) [session-id]
function mgres
    set -l work_dir $OBSIDIAN_VAULT
    if test -z "$work_dir"
        echo "mgres: OBSIDIAN_VAULT not set." >&2
        return 1
    end
    set -l mode $argv[1]
    set -l rest $argv[2..]
    set -l chat_prompt "$work_dir/claude/chat-mode-prompt.md"
    set -l code_prompt "$work_dir/claude/CODING.md"
    set -l prompt_args --system-prompt-file $chat_prompt

    switch $mode
        case chat
            # chat-mode base only
        case code
            set -a prompt_args --append-system-prompt-file $code_prompt
        case '*'
            echo "usage: mgres (chat|code) [session-id]" >&2
            return 1
    end

    if test -n "$TMUX"
        cd $work_dir
        CLAUDE_CODE_NO_FLICKER=1 claude $prompt_args --resume $rest
    else if tmux has-session -t mg 2>/dev/null
        tmux new-window -t mg -c $work_dir \
            "env CLAUDE_CODE_NO_FLICKER=1 claude $prompt_args --resume $rest; exec fish"
        tmux attach-session -t mg
    else
        tmux new-session -s mg -c $work_dir \
            "env CLAUDE_CODE_NO_FLICKER=1 claude $prompt_args --resume $rest; exec fish"
    end
end
