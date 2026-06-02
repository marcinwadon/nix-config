# Claude Code Statusline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Nord-colored single-line statusline to Claude Code, managed via Nix Home Manager.

**Architecture:** A new `home/programs/claude-code/default.nix` module declares the bash script via `home.file` and merges the `statusLine` key into `~/.claude/settings.json` via `home.activation`. Imported from `home/programs/default.nix`.

**Tech Stack:** Nix Home Manager, bash, jq (pinned via nix store path)

---

### Task 1: Create the claude-code Home Manager module

**Files:**
- Create: `home/programs/claude-code/default.nix`

- [ ] **Step 1: Create the module file**

```nix
{ pkgs, lib, ... }:
{
  home.file.".claude/statusline.sh" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      INPUT=$(cat)

      eval "$(echo "$INPUT" | ${pkgs.jq}/bin/jq -r '
        "MODEL=" + (.model.display_name // "claude" | @sh),
        "EFFORT=" + (.effort.level // "" | @sh),
        "CTX_PCT=" + ((.context_window.used_percentage // 0) | floor | tostring),
        "COST=" + (.cost.total_cost_usd // 0 | tostring),
        "DURATION_MS=" + (.cost.total_duration_ms // 0 | tostring),
        "LINES_ADDED=" + (.cost.total_lines_added // 0 | tostring),
        "LINES_REMOVED=" + (.cost.total_lines_removed // 0 | tostring),
        "VIM_MODE=" + (.vim.mode // "" | @sh),
        "CWD=" + (.cwd // "." | @sh),
        "WORKTREE_BRANCH=" + (.worktree.branch // "" | @sh)
      ')"

      # Context bar (10 blocks)
      FILLED=$((CTX_PCT / 10))
      [ $FILLED -gt 10 ] && FILLED=10
      EMPTY=$((10 - FILLED))
      BAR=""
      i=0; while [ $i -lt $FILLED ]; do BAR="$BAR▓"; i=$((i+1)); done
      i=0; while [ $i -lt $EMPTY  ]; do BAR="$BAR░"; i=$((i+1)); done

      # Git branch: prefer worktree field, fall back to git command
      if [ -n "$WORKTREE_BRANCH" ]; then
        BRANCH="$WORKTREE_BRANCH"
      else
        BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null || echo "")
      fi

      # Duration: show minutes above 60s, otherwise seconds
      if [ "$DURATION_MS" -ge 60000 ]; then
        DURATION_FMT="$((DURATION_MS / 60000))m"
      else
        DURATION_FMT="$((DURATION_MS / 1000))s"
      fi

      # Nerd font icons (UTF-8 byte sequences, no external tool needed)
      IC_MODEL=$(printf '\xef\x95\x84')   # U+F544  nf-fa-robot
      IC_EFFORT=$(printf '\xef\x83\xa7')  # U+F0E7  nf-fa-bolt
      IC_COST=$(printf '\xef\x85\x95')    # U+F155  nf-fa-usd
      IC_TIME=$(printf '\xef\x80\x97')    # U+F017  nf-fa-clock_o
      IC_GIT=$(printf '\xee\x82\xa0')     # U+E0A0  nf-dev-git_branch

      # Nord ANSI 256-color palette
      PURPLE='\033[38;5;139m'   # #b48ead
      ORANGE='\033[38;5;173m'   # #d08770
      BLUE='\033[38;5;110m'     # #88c0d0
      GREEN='\033[38;5;108m'    # #a3be8c
      YELLOW='\033[38;5;179m'   # #ebcb8b
      RED='\033[38;5;131m'      # #bf616a
      DIM='\033[38;5;59m'       # #4c566a
      RST='\033[0m'

      # Group 1: identity
      LINE="$PURPLE$IC_MODEL $MODEL$RST"
      [ -n "$EFFORT" ] && LINE="$LINE  $ORANGE$IC_EFFORT $EFFORT$RST"

      # Group 2: resources
      COST_FMT=$(printf '%.2f' "$COST")
      LINE="$LINE  $DIM│$RST  $BLUE$BAR $CTX_PCT%$RST  $GREEN$IC_COST $COST_FMT$RST  $DIM$IC_TIME $DURATION_FMT$RST"

      # Group 3: work
      LINE="$LINE  $DIM│$RST"
      if [ "$LINES_ADDED" -gt 0 ] || [ "$LINES_REMOVED" -gt 0 ]; then
        LINE="$LINE  $GREEN+$LINES_ADDED$RST $RED-$LINES_REMOVED$RST"
      fi
      [ -n "$BRANCH" ] && LINE="$LINE  $YELLOW$IC_GIT $BRANCH$RST"
      if [ -n "$VIM_MODE" ]; then
        case "$VIM_MODE" in
          NORMAL)        VIM_SHORT="NRM" ;;
          INSERT)        VIM_SHORT="INS" ;;
          VISUAL)        VIM_SHORT="VIS" ;;
          "VISUAL LINE") VIM_SHORT="V-L" ;;
          *)             VIM_SHORT="$VIM_MODE" ;;
        esac
        LINE="$LINE  $DIM$VIM_SHORT$RST"
      fi

      printf "%b\n" "$LINE"
    '';
  };

  home.activation.claudeStatuslineSettings =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      SETTINGS="$HOME/.claude/settings.json"
      SCRIPT_PATH="$HOME/.claude/statusline.sh"
      TMP=$(mktemp)
      if [ -f "$SETTINGS" ] && [ ! -L "$SETTINGS" ]; then
        ${pkgs.jq}/bin/jq --arg path "$SCRIPT_PATH" \
          '.statusLine = {"type":"command","command":$path}' \
          "$SETTINGS" > "$TMP" && mv "$TMP" "$SETTINGS"
      else
        ${pkgs.jq}/bin/jq -n --arg path "$SCRIPT_PATH" \
          '{"statusLine":{"type":"command","command":$path}}' \
          > "$SETTINGS"
      fi
    '';
}
```

- [ ] **Step 2: Verify nix parse is clean**

```bash
cd /path/to/nix-config
nix eval --file home/programs/claude-code/default.nix
```

Expected: no errors (output will be a lambda)

---

### Task 2: Wire the module into home/programs/default.nix

**Files:**
- Modify: `home/programs/default.nix`

- [ ] **Step 1: Add `./claude-code` to the imports list**

In `home/programs/default.nix`, add `./claude-code` to the returned list:

```nix
[
  ./git
  ./fish
  ./tmux
  ./zellij
  ./neovim-ide
  ./claude-code   # ← add this
  more
]
```

- [ ] **Step 2: Check the full flake evaluates**

```bash
nix flake check
```

Expected: exits 0 with no errors.

---

### Task 3: Smoke-test the script locally

**Files:** none (runtime test only)

- [ ] **Step 1: Run the script with a sample payload**

After deploying (`./switch home`), pipe sample JSON to the script:

```bash
echo '{
  "model": {"display_name": "claude-sonnet-4-6"},
  "effort": {"level": "max"},
  "context_window": {"used_percentage": 38},
  "cost": {"total_cost_usd": 0.42, "total_duration_ms": 750000,
           "total_lines_added": 84, "total_lines_removed": 12},
  "cwd": "/tmp",
  "worktree": {"branch": "main"}
}' | ~/.claude/statusline.sh
```

Expected: a single colored line resembling:
```
 claude-sonnet-4-6   max  │  ▓▓▓░░░░░░░ 38%   $0.42   12m  │  +84 -12   main
```

- [ ] **Step 2: Verify settings.json was updated**

```bash
jq '.statusLine' ~/.claude/settings.json
```

Expected:
```json
{
  "type": "command",
  "command": "/Users/<you>/.claude/statusline.sh"
}
```
