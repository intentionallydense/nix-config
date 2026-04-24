# Append a timestamped note to the Claude context log in the Obsidian vault.
# Usage: note "something worth remembering"
function note
    if test -z "$OBSIDIAN_VAULT"
        echo "note: OBSIDIAN_VAULT not set." >&2
        return 1
    end
    echo (date '+%Y-%m-%d %H:%M')" — $argv" >> "$OBSIDIAN_VAULT/claude/LOG.md"
end
