{ pkgs, lib, profile ? {}, ... }:
let
  shareConfig = profile.shareClaudeConfig or false;
in
{
  # Shared Claude Code config (read-only, from the repo) on the coding CTs.
  # Each file is symlinked individually (recursive = true) so the parent dirs
  # stay real, writable directories — Claude Code can still drop its own files
  # alongside ours (generated skills, plugin agents, etc.). The Mac is opted out
  # (shareClaudeConfig stays false) so it keeps its own live ~/.claude.
  # Dotted form + per-entry mkIf so these merge with the statusline.sh entry
  # below (a single `home.file = {…}` literal would conflict with it).
  home.file.".claude/CLAUDE.md" = lib.mkIf shareConfig { source = ./files/CLAUDE.md; };
  home.file.".claude/skills"    = lib.mkIf shareConfig { source = ./files/skills;   recursive = true; };
  home.file.".claude/commands"  = lib.mkIf shareConfig { source = ./files/commands; recursive = true; };
  home.file.".claude/agents"    = lib.mkIf shareConfig { source = ./files/agents;   recursive = true; };

  # Seed the memory-rule stubs as WRITABLE files (copy-if-absent), not symlinks,
  # so the auto-update memory rule can append to them per-machine. The shared
  # CLAUDE.md @-imports rules/memory-*.md; this guarantees those imports resolve
  # on a fresh CT. Never clobbers files that already exist (grown memory wins).
  home.activation.seedClaudeRules = lib.mkIf shareConfig (
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      RULES_DIR="$HOME/.claude/rules"
      SEED_DIR=${./files/rules-seed}
      mkdir -p "$RULES_DIR"
      for seed in "$SEED_DIR"/*.md; do
        dest="$RULES_DIR/$(basename "$seed")"
        if [ ! -e "$dest" ]; then
          install -m 0644 "$seed" "$dest"
        fi
      done
    ''
  );

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

      CTX_PCT=''${CTX_PCT:-0}
      CTX_PCT=''${CTX_PCT%%.*}

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

      # Nerd font icons (UTF-8 byte sequences)
      IC_MODEL=$(printf '\xef\x95\x84')   # U+F544  nf-fa-robot
      IC_EFFORT=$(printf '\xef\x83\xa7')  # U+F0E7  nf-fa-bolt
      IC_COST=$(printf '\xef\x85\x95')    # U+F155  nf-fa-usd
      IC_TIME=$(printf '\xef\x80\x97')    # U+F017  nf-fa-clock_o
      IC_GIT=$(printf '\xee\x82\xa0')     # U+E0A0  nf-dev-git_branch

      # Nord ANSI 256-color palette — ESC embedded via $'\033' (no printf %b)
      ESC=$'\033'
      PURPLE="$ESC[38;5;139m"   # #b48ead
      ORANGE="$ESC[38;5;173m"   # #d08770
      BLUE="$ESC[38;5;110m"     # #88c0d0
      GREEN="$ESC[38;5;108m"    # #a3be8c
      YELLOW="$ESC[38;5;179m"   # #ebcb8b
      RED="$ESC[38;5;131m"      # #bf616a
      DIM="$ESC[38;5;59m"       # #4c566a
      RST="$ESC[0m"

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

      printf "%s\n" "$LINE"
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
