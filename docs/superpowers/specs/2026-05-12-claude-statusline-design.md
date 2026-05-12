# Claude Code Statusline

## Goal

Configure Claude Code's built-in terminal statusline to show session context at a glance, deployed and version-controlled via Nix Home Manager.

## Scope

- New module: `home/programs/claude-code/default.nix`
- One-line addition to `home/programs/default.nix`
- No changes to any other modules

## Design Decisions

- **Surface:** Claude Code's own statusline (`statusLine` in `settings.json`), not tmux or the fish prompt
- **Layout:** Single dense line, all items visible, grouped with `│` separators
- **Colors:** Nord palette (matches existing tmux theme)
- **Icons:** Nerd font glyphs (available via `theme_nerd_fonts yes` in fish config)
- **Deployment:** Script via `home.file`, settings via `home.activation` merge

## Statusline Layout

```
 claude-sonnet-4-6  ⚡ max  │  ▓▓▓▓░░░░░░ 38%   $0.42   12m  │  +84-12   main  NRM
```

Three groups separated by `│`:

| Group | Items |
|---|---|
| Identity | model name, reasoning effort level |
| Resources | context bar + %, session cost, duration |
| Work | lines added/removed, git branch, vim mode |

### Items

| Item | Source field | Notes |
|---|---|---|
| Model | `model.display_name` | Always shown, purple |
| Effort | `effort.level` | Omitted if field absent (not all sessions have it) |
| Context bar | `context_window.used_percentage` | 10-block `▓░` bar + integer %, blue |
| Cost | `cost.total_cost_usd` | `$0.00` format, green |
| Duration | `cost.total_duration_ms` | `12m` or `45s` (seconds when under 1 min), dim |
| Lines changed | `cost.total_lines_added`, `cost.total_lines_removed` | `+N-N`, omitted if both zero |
| Git branch | `worktree.branch` → fallback `git branch --show-current` in `cwd` | yellow |
| Vim mode | `vim.mode` | Abbreviated (`NRM`/`INS`/`VIS`/`V-L`), omitted if absent |

### Nord Colors (ANSI)

| Role | Color | Hex | ANSI 256 |
|---|---|---|---|
| Model | Purple | `#b48ead` | 139 |
| Effort | Orange | `#d08770` | 173 |
| Context bar | Blue | `#88c0d0` | 110 |
| Cost, lines+ | Green | `#a3be8c` | 108 |
| Git branch | Yellow | `#ebcb8b` | 179 |
| Lines- | Red | `#bf616a` | 131 |
| Duration, separators, vim | Dim | `#4c566a` | 59 |

## Components

### 1. `home/programs/claude-code/default.nix`

Declares two things:

**Script — `home.file.".claude/statusline.sh"`**

- `executable = true`
- Uses `${pkgs.jq}/bin/jq` by store path (no PATH dependency)
- Single `jq` eval call to parse all fields in one pass
- Builds the line with `printf "%b"` for ANSI color output
- Conditional rendering: effort, lines changed, and vim mode are omitted when their source fields are absent or zero

**Settings merge — `home.activation.claudeStatuslineSettings`**

- Runs after `writeBoundary`
- Merges `{"statusLine":{"type":"command","command":"~/.claude/statusline.sh"}}` into the existing `~/.claude/settings.json` using `jq `. + {...}`
- Writes via a temp file + `mv` (atomic)
- Guard: only runs if the file exists and is not a symlink (so it never clobbers a Nix-managed file)
- Idempotent: re-running `./switch home` overwrites the key with the same value

`settings.json` remains a plain file (not a symlink) so Claude Code can still write to it.

### 2. `home/programs/default.nix`

Add `./claude-code` to the imports list.

## Deployment

```bash
./switch home
```

The activation script runs after the switch, merging the `statusLine` key into `settings.json`. The next Claude Code session picks it up automatically.

## Non-Goals

- tmux status bar integration
- Fish prompt changes
- Neovim statusline
- Rate limit display (Claude.ai subscriber-only field)
