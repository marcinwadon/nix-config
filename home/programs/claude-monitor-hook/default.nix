# claude-monitor lifecycle hook wiring.
#
# Enabled only when the profile sets `monitorMachine` (the collector-only
# "monitor" box and any unconfigured profile leave it null → no-op). Installs
# the hook binary and merges the Claude Code lifecycle hooks into
# ~/.claude/settings.json non-destructively (same jq-merge pattern as the
# statusline activation), pointing each at a per-machine wrapper. PostToolUse is
# wired so the collector sees mid-turn activity — without it, a session that
# resumes after a permission/idle Notification stays "needs_attention" until the
# turn ends, and the final assistant message can't be streamed early.
#
# The wrapper carries the non-secret MONITOR_URL/MONITOR_MACHINE as literals and
# reads MONITOR_TOKEN from a file at RUNTIME — sops (/run/secrets/monitor_token)
# on Linux containers, ~/.config/claude-monitor/token on darwin (no sops there).
# Nothing secret is baked into the Nix store.
{
  pkgs,
  lib,
  config,
  profile ? {},
  ...
}: let
  defaults = import ../../lib/profile-defaults.nix;
  p = lib.recursiveUpdate defaults profile;
  machine = p.monitorMachine;
  enable = machine != null;

  tokenFile =
    if pkgs.stdenv.isLinux
    then "/run/secrets/monitor_token"
    else "${config.home.homeDirectory}/.config/claude-monitor/token";

  wrapper = pkgs.writeShellScript "claude-monitor-hook-wrapper" ''
    [ -r "${tokenFile}" ] && export MONITOR_TOKEN="$(cat "${tokenFile}")"
    export MONITOR_URL="${p.monitorUrl}"
    export MONITOR_MACHINE="${toString machine}"
    exec ${pkgs.claude-monitor-hook}/bin/claude-monitor-hook
  '';

  # The tailer is a long-running service (not a hook): it fsnotify-watches active
  # transcript files and streams content in near-real-time. Same env contract as
  # the hook wrapper.
  tailWrapper = pkgs.writeShellScript "claude-monitor-tail-wrapper" ''
    [ -r "${tokenFile}" ] && export MONITOR_TOKEN="$(cat "${tokenFile}")"
    export MONITOR_URL="${p.monitorUrl}"
    export MONITOR_MACHINE="${toString machine}"
    exec ${pkgs.claude-monitor-hook}/bin/claude-monitor-tail
  '';
in
  lib.mkIf enable (lib.mkMerge [
    {
      home.packages = [pkgs.claude-monitor-hook];

      # Runs after claudeStatuslineSettings (same file) so that key is preserved.
      home.activation.claudeMonitorHooks = lib.hm.dag.entryAfter ["writeBoundary" "claudeStatuslineSettings"] ''
        SETTINGS="$HOME/.claude/settings.json"
        TMP=$(mktemp)
        BASE="$TMP.base"
        if [ -f "$SETTINGS" ] && [ ! -L "$SETTINGS" ]; then
          SRC="$SETTINGS"
        else
          echo '{}' > "$BASE"
          SRC="$BASE"
        fi
        ${pkgs.jq}/bin/jq --arg cmd '${wrapper}' '
          .hooks = ((.hooks // {})
            | .SessionStart     = [{"hooks":[{"type":"command","command":$cmd}]}]
            | .UserPromptSubmit = [{"hooks":[{"type":"command","command":$cmd}]}]
            | .PostToolUse      = [{"hooks":[{"type":"command","command":$cmd}]}]
            | .Stop             = [{"hooks":[{"type":"command","command":$cmd}]}]
            | .Notification     = [{"hooks":[{"type":"command","command":$cmd}]}]
            | .SessionEnd       = [{"hooks":[{"type":"command","command":$cmd}]}])
        ' "$SRC" > "$TMP" && mv "$TMP" "$SETTINGS"
        rm -f "$BASE"
      '';
    }
    # Linux CTs: systemd user service (needs lingering for marcin — set in
    # lxc-base). Gated on `machine` (a pure profile value), NOT pkgs.stdenv:
    # deciding module structure off pkgs.stdenv forces config.nixpkgs and
    # infinite-recurses. machine=="mac" is the darwin proxy (only the Mac sets it).
    (lib.optionalAttrs (enable && machine != "mac") {
      systemd.user.services.claude-monitor-tail = {
        Unit.Description = "claude-monitor transcript tailer";
        Service = {
          ExecStart = "${tailWrapper}";
          Restart = "on-failure";
          RestartSec = 3;
        };
        Install.WantedBy = ["default.target"];
      };
    })
    # Mac: launchd agent.
    (lib.optionalAttrs (machine == "mac") {
      launchd.agents.claude-monitor-tail = {
        enable = true;
        config = {
          ProgramArguments = ["${tailWrapper}"];
          RunAtLoad = true;
          KeepAlive = true;
        };
      };
    })
  ])
