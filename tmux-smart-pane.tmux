#!/usr/bin/env bash
# TPM plugin entry point. Sets up the @last_seen hook and keybindings.
# Override keys in tmux.conf before this run line (see README).
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_get_opt() {
    local val
    val=$(tmux show-option -gqv "$1" 2>/dev/null)
    echo "${val:-$2}"
}

tmux set-option -g focus-events on
tmux set-hook -g pane-focus-in \
    'run-shell "tmux set-option -p -t #{pane_id} @last_seen $(date +%s)"'

UNDO_KEY=$(_get_opt "@smart-pane-undo-swap-key" "P")
JUMP_SESSION_KEY=$(_get_opt "@smart-pane-jump-session-key" "s")
JUMP_PANE_KEY=$(_get_opt "@smart-pane-jump-pane-key" "p")

tmux bind "$UNDO_KEY" run-shell \
    "$CURRENT_DIR/scripts/undo-swap-pane.sh"
tmux bind "$JUMP_SESSION_KEY" display-popup -w "100%" -h "100%" -b none \
    -E "$CURRENT_DIR/scripts/jump-session.sh"
tmux bind "$JUMP_PANE_KEY" display-popup -w "100%" -h "100%" -b none \
    -E "$CURRENT_DIR/scripts/jump-pane.sh"
