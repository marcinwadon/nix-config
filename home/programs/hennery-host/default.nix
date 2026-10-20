# hennery host (`hennery host run`) as a per-user service: a launchd agent on
# the Mac, a systemd user service on the M1 users. Runs ALONGSIDE the
# claude-monitor host (../claude-monitor-hook), sharing nothing with it.
#
# Enabled only when the profile sets `henneryHost`. Declarative stand-in for
# what `hennery service install --role host` would write (crates/hennery/src/
# service/unit.rs at v0.1.4), with these deliberate differences:
#
# - Named `hennery-host-nix`, not hennery's own `dev.hennery.host` /
#   `hennery-host.service`. hennery's `service status|install|uninstall` act on
#   exactly those file names, and would rewrite or delete a home-manager-owned
#   symlink. Never run `hennery service install` on a machine using this.
# - PATH is spelled out rather than captured from a login shell at install
#   time: the same directories the Mac's fish login shell yields, plus the
#   per-user profile, so the agents' `sh`, git and toolchains resolve. Same
#   reasoning as the claude-monitor host's hostPath.
# - Unpaired is the normal first state (`host join` is run by hand, later):
#   `host run` then exits 1 at once. systemd backs off exponentially to 10 min;
#   launchd has no backoff, so the wrapper itself waits 5 min before failing.
# - `--data-dir` is passed explicitly, set to hennery's platform default, so the
#   unit, the pairing check below and `hennery host join --data-dir …` all name
#   one directory without hennery's own lookup deciding.
{
  pkgs,
  lib,
  config,
  profile ? {},
  ...
}: let
  defaults = import ../../lib/profile-defaults.nix;
  p = lib.recursiveUpdate defaults profile;
  enable = p.henneryHost;
  isDarwin = p.isDarwin;

  home = config.home.homeDirectory;

  # hennery's platform default (distribution spec §8).
  dataDir =
    if isDarwin
    then "${home}/Library/Application Support/hennery"
    else "${config.xdg.dataHome}/hennery";

  hostPath = lib.concatStringsSep ":" [
    "${home}/.local/bin"
    "${home}/.nix-profile/bin"
    "/etc/profiles/per-user/${config.home.username}/bin"
    "/run/current-system/sw/bin"
    "/nix/var/nix/profiles/default/bin"
    "/usr/local/bin"
    "/usr/bin"
    "/bin"
    "/usr/sbin"
    "/sbin"
  ];

  roots = lib.concatMapStringsSep " " (r: "--workspace-root ${lib.escapeShellArg r}") p.henneryWorkspaceRoots;

  # HENNERY_SERVICE makes hennery log to its own rotated files (~/Library/Logs/
  # hennery on darwin, ~/.local/state/hennery/log on Linux), and under launchd
  # makes a revoked host exit 0 instead of 78, so `SuccessfulExit = false`
  # keeps it down rather than respawning it into the same refusal.
  wrapper = pkgs.writeShellScript "hennery-host-run" ''
    export PATH="${hostPath}"
    export SHELL="${config.programs.fish.package}/bin/fish"
    export HENNERY_SERVICE="${
      if isDarwin
      then "launchd"
      else "systemd"
    }"
    ${lib.optionalString isDarwin ''
      if [ ! -f ${lib.escapeShellArg "${dataDir}/host.toml"} ]; then
        echo "hennery-host-nix: no pairing in ${dataDir} yet; run \`hennery host join --data-dir '${dataDir}' <url>\`. Checking again in 5 min." >&2
        sleep 300
        exit 1
      fi
    ''}
    exec ${pkgs.hennery}/bin/hennery host run --data-dir ${lib.escapeShellArg dataDir} ${roots}
  '';
in
  lib.mkIf enable (lib.mkMerge [
    {
      # The CLI for `hennery host join` / `host adapters` / `doctor`.
      home.packages = [pkgs.hennery];
    }
    # Gated on a pure profile value, not pkgs.stdenv (infinite recursion).
    (lib.optionalAttrs (!isDarwin) {
      systemd.user.services.hennery-host-nix = {
        Unit = {
          Description = "hennery host";
          # hennery's unit caps starts at 10 per 300 s; the backoff below
          # already bounds the rate, and a cap would leave an unpaired host
          # `failed` for good instead of picking up a later join.
          StartLimitIntervalSec = 0;
        };
        Service = {
          Type = "exec";
          ExecStart = "${wrapper}";
          Restart = "on-failure";
          # 78 = revoked by the collector: re-pair by hand, don't retry.
          RestartPreventExitStatus = 78;
          # 5 s growing to 10 min. The step counter only resets on a manual
          # start, so restart the unit by hand after `hennery host join`.
          RestartSec = 5;
          RestartSteps = 10;
          RestartMaxDelaySec = "10min";
          # Lets the host park its sessions and stop its adapters before
          # systemd kills what is left.
          KillMode = "mixed";
          TimeoutStopSec = 30;
        };
        Install.WantedBy = ["default.target"];
      };
    })
    (lib.optionalAttrs isDarwin {
      launchd.agents.hennery-host-nix = {
        enable = true;
        config = {
          ProgramArguments = ["${wrapper}"];
          RunAtLoad = true;
          KeepAlive = {SuccessfulExit = false;};
          ThrottleInterval = 10;
          # Time for the host to park sessions and stop adapters.
          ExitTimeOut = 30;
          # GUI login session only: the login keychain is unlocked there.
          LimitLoadToSessionType = "Aqua";
          # Crash/early output only; hennery's own log is ~/Library/Logs/hennery.
          StandardOutPath = "${home}/Library/Logs/hennery-host-nix.log";
          StandardErrorPath = "${home}/Library/Logs/hennery-host-nix.log";
        };
      };
    })
  ])
