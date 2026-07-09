# deploy-monitor — bump the claude-monitor flake input, ship flake.lock to the
# monitor box (and, with --fleet, the 3 CTs + Mac host), and rebuild. Must be
# run from inside the nix-config repo. Leaves flake.lock uncommitted (the
# operator signs+commits nix-config main). Default deploys only the collector
# on the box; --fleet also rebuilds every per-machine host (the path taken when
# the diff touches cmd/host or internal/hostlink).
{pkgs, ...}: let
  gh = "${pkgs.gh}/bin/gh";
  git = "${pkgs.git}/bin/git";
  ssh = "${pkgs.openssh}/bin/ssh";
  jq = "${pkgs.jq}/bin/jq";
  curl = "${pkgs.curl}/bin/curl";
  nix = "${pkgs.nix}/bin/nix";
in
  pkgs.writeShellScriptBin "deploy-monitor" ''
    set -euo pipefail

    fleet=0; bump=1; dry_run=0
    for a in "$@"; do
      case "$a" in
        --fleet)   fleet=1 ;;
        --no-bump) bump=0 ;;
        --dry-run) dry_run=1 ;;
        *) echo "usage: deploy-monitor [--fleet] [--no-bump] [--dry-run]" >&2; exit 1 ;;
      esac
    done

    toplevel="$(${git} rev-parse --show-toplevel)"
    if ! grep -q 'claude-monitor' "$toplevel/flake.nix"; then
      echo "error: $toplevel is not the nix-config repo (no claude-monitor input)" >&2
      exit 1
    fi
    cd "$toplevel"

    TOK="$(${gh} auth token)"
    [ -n "$TOK" ] || { echo "error: gh auth token returned empty" >&2; exit 1; }

    BOX="root@10.0.1.123"
    CTS=( "root@10.0.1.120:personal" "root@10.0.1.121:evojam" "root@10.0.1.122:parloa" )

    ship_lock() { # $1 = ssh target
      echo "+ ship flake.lock -> $1:/root/nix-config/flake.lock" >&2
      [ "$dry_run" -eq 1 ] && return 0
      ${ssh} "$1" "cat > /root/nix-config/flake.lock" < flake.lock
    }

    rebuild_remote() { # $1 = ssh target, $2 = flake attr
      echo "+ rebuild $1 -> nixos-rebuild switch --flake .#$2" >&2
      [ "$dry_run" -eq 1 ] && return 0
      ${ssh} "$1" bash -s <<EOF
set -euo pipefail
export NIX_CONFIG="access-tokens = github.com=$TOK"
cd /root/nix-config
nixos-rebuild switch --flake .#$2 --max-jobs 1 --cores 2
EOF
    }

    if [ "$bump" -eq 1 ]; then
      oldrev="$(${jq} -r '.nodes."claude-monitor".locked.rev // "unknown"' flake.lock)"
      echo "+ bump claude-monitor (was ''${oldrev:0:12})" >&2
      if [ "$dry_run" -eq 0 ]; then
        NIX_CONFIG="access-tokens = github.com=$TOK" ${nix} flake update claude-monitor
        newrev="$(${jq} -r '.nodes."claude-monitor".locked.rev // "unknown"' flake.lock)"
        echo "  claude-monitor: ''${oldrev:0:12} -> ''${newrev:0:12}" >&2
      fi
    else
      echo "+ skip bump (--no-bump)" >&2
    fi

    # Collector (always)
    ship_lock "$BOX"
    rebuild_remote "$BOX" monitor

    # Fleet (hosts) — only with --fleet
    if [ "$fleet" -eq 1 ]; then
      for entry in "''${CTS[@]}"; do
        target="''${entry%:*}"; attr="''${entry##*:}"
        ship_lock "$target"
        rebuild_remote "$target" "$attr"
      done
      echo "+ deploy Mac host -> ./switch home" >&2
      [ "$dry_run" -eq 0 ] && ./switch home
    fi

    # Verify
    echo "+ verify: GET http://10.0.1.123:8787/api/machines" >&2
    if [ "$dry_run" -eq 0 ]; then
      ${curl} -fsS http://10.0.1.123:8787/api/machines | ${jq} . \
        || echo "warning: could not fetch /api/machines" >&2
    fi

    echo "done." >&2
  ''
