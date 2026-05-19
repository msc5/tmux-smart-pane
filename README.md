# tmux-smart-pane

Smart pane navigation for tmux: fzf-powered pane swapping and a session/pane jump picker.

## Features

- **Swap pane** — fzf picker showing all other panes sorted by recency; swaps the current pane with the selection
- **Undo swap** — reverses the last swap (acts as a toggle)
- **Jump** — fzf picker with session and pane views; press `Ctrl-L` to toggle between them

Both the swap picker and the jump picker's pane view share the same `@last_seen`-sorted listing.

## Requirements

- tmux 3.2+
- fzf
- bash 4+ (macOS ships bash 3; install via `brew install bash`)

## Installation

### Local (manual)

1. Clone into `~/.config/tmux/plugins/tmux-smart-pane` — git preserves execute bits so no `chmod` is needed
2. Add to `tmux.conf` before the TPM `run` line:
   ```
   run "~/.config/tmux/plugins/tmux-smart-pane/tmux-smart-pane.tmux"
   ```
3. Reload tmux: `<prefix> R`

### With TPM (from a published repo)

```
set -g @plugin 'yourname/tmux-smart-pane'
```

Then add keybindings as above and run `<prefix> I` to install.

## Configuration

Set options in `tmux.conf` **before** the `run` line:

| Option | Default | Description |
|--------|---------|-------------|
| `@smart-pane-swap-key` | `p` | Key to open swap-pane picker |
| `@smart-pane-undo-swap-key` | `P` | Key to undo last swap |
| `@smart-pane-jump-key` | `s` | Key to open jump picker |
| `@smart-pane-cache-path` | `~/.local/share/tmux-smart-pane/cache.sh` | Swap-history cache location |

```
set -g @smart-pane-swap-key "w"
run "~/.config/tmux/plugins/tmux-smart-pane/tmux-smart-pane.tmux"
```

## Scripts

The scripts can also be called directly:

| Script | Description |
|--------|-------------|
| `scripts/jump-list.sh sessions` | Print session listing for fzf |
| `scripts/jump-list.sh panes` | Print pane listing for fzf (sorted by recency) |
| `scripts/pick-pane.sh` | fzf pane picker: reads `pane_id\|display` from stdin, prints selected `pane_id` |
