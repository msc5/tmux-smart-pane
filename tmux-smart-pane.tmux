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

SWAP_KEY=$(_get_opt "@smart-pane-swap-key" "p")
UNDO_KEY=$(_get_opt "@smart-pane-undo-swap-key" "P")
JUMP_KEY=$(_get_opt "@smart-pane-jump-key" "s")
LOCK_KEY=$(_get_opt "@smart-pane-lock-key" "M-=")

tmux bind "$SWAP_KEY" display-popup -w "100%" -h "100%" -b none \
    -E "$CURRENT_DIR/scripts/swap-pane.sh"
tmux bind "$UNDO_KEY" run-shell \
    "$CURRENT_DIR/scripts/undo-swap-pane.sh"
tmux bind "$JUMP_KEY" display-popup -w "100%" -h "100%" -b none \
    -E "$CURRENT_DIR/scripts/jump-pane.sh"

# Pass-through lock: disables outer prefix/keytable so keys flow to nested session.
# Toggle with LOCK_KEY (default M-=); a second press restores normal behaviour.
tmux source-file - <<EOF
bind -T root $LOCK_KEY \
    set prefix None \; \
    set key-table off \; \
    set @client_locked 1 \; \
    if -F '#{pane_in_mode}' 'send-keys -X cancel' \; \
    refresh-client -S

bind -T off $LOCK_KEY \
    set -u prefix \; \
    set -u key-table \; \
    set -u status-left \; \
    set @client_locked 0 \; \
    refresh-client -S
EOF
