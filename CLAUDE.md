# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A tmux plugin (bash) that provides fzf-powered pane swapping and a session/pane jump picker with first-class remote session support. No build system, no test suite — changes are tested by reloading tmux.

## Development workflow

Reload the plugin after changes:
```
tmux source ~/.config/tmux/tmux.conf   # or your tmux.conf path
```

Test a script directly (must be run inside a tmux session):
```bash
bash scripts/jump-list.sh sessions
bash scripts/jump-list.sh panes
```

Requirements: tmux 3.2+, fzf, bash 4+ (macOS ships bash 3 — use `/opt/homebrew/bin/bash`).

## Architecture

**Entry point** — `tmux-smart-pane.tmux`  
Sets up the `pane-focus-in` hook (writes `@last_seen` unix timestamp as a pane option), reads config options, and registers all keybindings. Also configures the pass-through lock mode (`M-=` by default) that disables the outer prefix so keystrokes flow to a nested tmux session.

**`scripts/helpers.sh`** — sourced by all other scripts, never executed directly.  
Sets `PLUGIN_DIR` (canonical path to the plugin root) and shared variables (`SMART_PANE_CACHE`, `REMOTE_SESSIONS_CACHE_PATH`). Also applies the `@smart-pane-cache-path` tmux option override at source time.  
Key functions:
- `_humanize_seconds` — formats a duration for display
- `_tmux_fg_cmd_lines` — single `ps` pass to map `tty → foreground command` for all panes
- `_sed_inplace` — portable in-place sed wrapper (GNU sed uses `-i`, BSD sed requires `-i ''`)

**`scripts/connect-remote.sh`** — runs outside tmux (in the bare terminal after `detach-client -E`).  
Args: `host sess saved-session`. Establishes an SSH session to the remote, sets `TMSP_MANAGED=1` in the remote tmux environment (so that `prefix + s` on the remote detaches rather than opening fzf), waits for the SSH session to exit, updates the remote-session recency cache, then re-attaches by exec-ing `jump-session.sh --standalone`.

**`TMSP_MANAGED` signal** — `connect-remote.sh` sets `TMSP_MANAGED=1` via `tmux set-environment -g` before `new-session`. `jump-session.sh` on the remote checks for this variable and, when set, simply detaches the client and exits — returning the terminal to `connect-remote.sh` on the local machine so it can re-open the picker.

**ControlMaster** — the plugin relies on the user's `~/.ssh/config` for ControlMaster/ControlPath/ControlPersist. No socket paths are hardcoded. When configured, remote session queries in `jump-list.sh` and preview fetches in `preview.sh` reuse the existing SSH channel and are near-instant.

**Recency tracking for remote sessions** — `connect-remote.sh` updates the sort timestamp in the flat cache file (`REMOTE_SESSIONS_CACHE_PATH`) after each connection, so recently visited remote sessions sort to the top of the picker on next open.

**Cache** — a bash `declare -A CACHE` file at `~/.local/share/tmux-smart-pane/cache.sh` (overridable via `@smart-pane-cache-path`). Currently only stores `CACHE[swap-pane]="src:target"` for undo.

**Data flow through fzf pickers**  
`jump-list.sh` emits rows in the internal format `<sort_key>|<id>|<display>`, sorts on `k1`, then strips the sort key with `cut -d'|' -f2-` before handing rows to fzf. fzf is configured with `--delimiter='|' --with-nth=2..` so only the display column is visible. The selected line is split on `|` to recover the `pane_id`.

Remote session IDs use the prefix `remote:<host>:<session>` throughout the pipeline; `jump-session.sh`, `preview.sh`, and `connect-remote.sh` all check for this prefix to route differently.

**Script responsibilities**

| Script | Role |
|---|---|
| `jump-list.sh sessions` | Local sessions + remote sessions via parallel SSH |
| `jump-list.sh panes` | All panes except current, sorted by `@last_seen` recency |
| `jump-session.sh` | Full-screen fzf popup for sessions; handles both normal (popup) and `--standalone` (bare terminal) modes; routes remote selections to `connect-remote.sh` |
| `jump-pane.sh` | Full-screen fzf popup for panes; `Enter` jumps, `Tab` swaps via `swap-pane.sh` |
| `swap-pane.sh` | Swaps two panes and records the pair in the undo cache |
| `undo-swap-pane.sh` | Reads cache, reverses the stored swap pair via `swap-pane.sh` |
| `connect-remote.sh` | Runs outside tmux; manages SSH lifecycle and local re-attach |
| `preview.sh` | `tmux capture-pane` for local panes; SSH capture for remote sessions |
