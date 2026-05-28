#!/usr/bin/env bash
# Kill the tmux session that owns the given pane ID,
# but first gracefully close any Neovim instances.
# Called from jump-session.sh's ctrl-x fzf binding.

set -euo pipefail

p="$1"
[[ "$p" == %* ]] || exit 0

sess=$(tmux display-message -p -t "$p" "#{session_name}" 2>/dev/null)
[[ -n "$sess" ]] || exit 0

nvim_panes=()

while read -r pane_id cmd; do
    case "$cmd" in
        nvim|vim)
            nvim_panes+=("$pane_id")
            tmux send-keys -t "$pane_id" Escape ":qa" Enter
            ;;
    esac
done < <(
    tmux list-panes -t "$sess" -F "#{pane_id} #{pane_current_command}"
)

# Wait up to ~2 seconds for nvim to exit cleanly
for _ in {1..20}; do
    remaining=0

    for pane_id in "${nvim_panes[@]}"; do
        cmd=$(tmux display-message -p -t "$pane_id" "#{pane_current_command}" 2>/dev/null || true)

        if [[ "$cmd" == "nvim" || "$cmd" == "vim" ]]; then
            remaining=1
            break
        fi
    done

    [[ $remaining -eq 0 ]] && break
    sleep 0.1
done

tmux kill-session -t "$sess"
