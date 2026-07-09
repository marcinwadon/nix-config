# Ops Scripts (`deploy-monitor` + `gpush`) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add two Mac-side `writeShellScriptBin` ops scripts to nix-config — `gpush` (push to the correct GitHub account over HTTPS, dodging the Yubikey) and `deploy-monitor` (bump + ship + rebuild the claude-monitor fleet).

**Architecture:** Each script is a `pkgs.writeShellScriptBin` derivation in `home/scripts/`, `callPackage`'d into the existing `p.isDarwin` list in `home/scripts/default.nix` (same wiring/gating as `aws-evojam-mfa.nix`). External tools are referenced by absolute Nix store path. Both scripts accept `--dry-run` to print the resolved plan without executing.

**Tech Stack:** Nix (`writeShellScriptBin`), bash (nixpkgs bash 5.x — modern array/`set -u` semantics), `gh`, `git`, `openssh`, `jq`, `curl`.

## Global Constraints

- Both scripts are **Darwin-only** — added under the `p.isDarwin` branch of `home/scripts/default.nix`. Run from the Mac.
- Every script starts with `set -euo pipefail`.
- External tools referenced by absolute store path via `let` bindings (`${pkgs.gh}/bin/gh`, `${pkgs.git}/bin/git`, `${pkgs.openssh}/bin/ssh`, `${pkgs.jq}/bin/jq`, `${pkgs.curl}/bin/curl`, `${pkgs.nix}/bin/nix`).
- Nix `''` indented-string escaping: shell `$var` and `$1`/`$@` pass through literally; shell `${...}` MUST be written `''${...}`; a literal `''` is written `'''`. Backslashes are literal in `''` strings (so `\"` and `\$` emit `\"` and `\$` to the script, which is what bash needs).
- Configuration constants (machine IPs, flake attrs, owner→account map) live as bash `let`/assignment lines near the top of the script body, easy to audit.
- Commits: Conventional Commits, personal repo, no ticket scope. Do NOT commit `flake.lock` (it has a pending operator bump) — stage only the files each task creates/modifies.
- Branch already exists: `feat/ops-scripts-deploy-monitor-gpush`. The spec is already committed on it.
- Owner→account map: `marcinwadon→marcinwadon`, `parloa→marcin-wadon-parloa`, `evojam→marcinwadon`, unknown→active account (warn).
- Fleet topology: box `root@10.0.1.123` → `.#monitor`; personal `root@10.0.1.120` → `.#personal`; evojam `root@10.0.1.121` → `.#evojam`; parloa `root@10.0.1.122` → `.#parloa`; Mac → `./switch home`. Remote rebuilds use `--max-jobs 1 --cores 2`.

---

### Task 1: `gpush` — push under the correct account over HTTPS

**Files:**
- Create: `home/scripts/gpush.nix`
- Modify: `home/scripts/default.nix` (add `gpush` to the `p.isDarwin` list)

**Interfaces:**
- Consumes: nothing from other tasks.
- Produces: a `gpush` binary on the Mac PATH. `gpush [--dry-run] [extra git-push flags…]` — pushes the current branch to `origin`'s repo under the mapped account.

- [ ] **Step 1: Create `home/scripts/gpush.nix`**

```nix
# gpush — push the current branch to origin's repo under the correct GitHub
# account, via an explicit HTTPS URL so SSH-origin (Yubikey-gated) repos don't
# prompt for a touch, and so HTTPS-origin repos don't resolve to the wrong gh
# account. The account's token is resolved at push time inside a credential
# helper (never placed in argv). A bare --force-with-lease is auto-pinned to
# the current remote SHA (pushing via an ad-hoc URL otherwise triggers a
# "stale info" rejection because origin's lease ref is stale).
{pkgs, ...}: let
  gh = "${pkgs.gh}/bin/gh";
  git = "${pkgs.git}/bin/git";
in
  pkgs.writeShellScriptBin "gpush" ''
    set -euo pipefail

    dry_run=0
    args=()
    for a in "$@"; do
      case "$a" in
        --dry-run) dry_run=1 ;;
        *) args+=("$a") ;;
      esac
    done

    origin="$(${git} remote get-url origin)"
    ownerrepo="$(printf '%s' "$origin" \
      | sed -E 's#^git@github\.com:##; s#^https://github\.com/##; s#\.git$##')"
    case "$ownerrepo" in
      */*) : ;;
      *) echo "error: origin '$origin' is not a github.com remote" >&2; exit 1 ;;
    esac
    owner="''${ownerrepo%%/*}"
    repo="''${ownerrepo#*/}"

    case "$owner" in
      marcinwadon) acct="marcinwadon" ;;
      parloa)      acct="marcin-wadon-parloa" ;;
      evojam)      acct="marcinwadon" ;;
      *)
        acct="$(${gh} api user --jq .login)"
        echo "warning: unknown owner '$owner'; using active gh account '$acct'" >&2
        ;;
    esac

    # Resolve how to fetch this account's token: keyring accounts answer to
    # --user; an env-var/active account (e.g. marcinwadon via GITHUB_TOKEN)
    # only answers to bare `gh auth token`.
    if ${gh} auth token --user "$acct" >/dev/null 2>&1; then
      token_cmd="${gh} auth token --user $acct"
    elif [ "$acct" = "$(${gh} api user --jq .login 2>/dev/null || true)" ]; then
      token_cmd="${gh} auth token"
    else
      echo "error: gh account '$acct' not available; run: gh auth login" >&2
      exit 1
    fi

    helper="!f(){ echo username=$acct; echo \"password=\$($token_cmd)\"; }; f"

    branch="$(${git} branch --show-current)"
    [ -n "$branch" ] || { echo "error: detached HEAD; check out a branch" >&2; exit 1; }
    refspec="HEAD:$branch"
    url="https://github.com/$owner/$repo.git"

    pinned_args=()
    for a in "''${args[@]:-}"; do
      if [ "$a" = "--force-with-lease" ]; then
        remote_sha="$(${git} -c credential.helper= -c credential.helper="$helper" \
          ls-remote "$url" "$branch" | awk '{print $1}')"
        if [ -n "$remote_sha" ]; then
          pinned_args+=("--force-with-lease=$branch:$remote_sha")
        else
          pinned_args+=("--force-with-lease")
        fi
      else
        pinned_args+=("$a")
      fi
    done

    echo "gpush: $owner/$repo  branch=$branch  account=$acct" >&2
    echo "  url=$url  refspec=$refspec  extra=''${pinned_args[*]:-}" >&2
    if [ "$dry_run" -eq 1 ]; then
      echo "  (dry-run: not pushing)" >&2
      exit 0
    fi

    ${git} -c credential.helper= -c credential.helper="$helper" \
      push "$url" "$refspec" "''${pinned_args[@]:-}"
  ''
```

- [ ] **Step 2: Wire `gpush` into `home/scripts/default.nix`**

Modify the `p.isDarwin` list to add the `gpush` line:

```nix
      ++ lib.optionals p.isDarwin [
        (pkgs.callPackage ./aws-evojam-mfa.nix {})
        (pkgs.callPackage ./gpush.nix {})
      ]
```

- [ ] **Step 3: Build the home activation package (proves it compiles + wires)**

Run: `nix build .#homeConfigurations.marcinwadon.activationPackage`
Expected: builds successfully; `./result/home-path/bin/gpush` exists.
Verify: `test -x ./result/home-path/bin/gpush && echo OK`

- [ ] **Step 4: Assert the resolved plan via `--dry-run` (behavioral test)**

Run from the nix-config repo itself (origin owner = `marcinwadon`):
```bash
./result/home-path/bin/gpush --dry-run 2>&1
```
Expected output contains: `account=marcinwadon`, `url=https://github.com/marcinwadon/nix-config.git`, and `(dry-run: not pushing)`. It must NOT push.

If a parloa or evojam checkout is available locally, also run `gpush --dry-run` there and confirm `account=marcin-wadon-parloa` / `account=marcinwadon` respectively. (Optional — nix-config alone proves the marcinwadon mapping + HTTPS-URL construction.)

- [ ] **Step 5: Commit**

```bash
git add home/scripts/gpush.nix home/scripts/default.nix
git commit -m "feat(scripts): add gpush (push under correct gh account over https)"
```

---

### Task 2: `deploy-monitor` — bump + ship + rebuild the claude-monitor fleet

**Files:**
- Create: `home/scripts/deploy-monitor.nix`
- Modify: `home/scripts/default.nix` (add `deploy-monitor` to the `p.isDarwin` list)

**Interfaces:**
- Consumes: nothing from Task 1 (independent). Reuses the repo's `./switch home` for the Mac host.
- Produces: a `deploy-monitor` binary on the Mac PATH. `deploy-monitor [--fleet] [--no-bump] [--dry-run]`.

- [ ] **Step 1: Create `home/scripts/deploy-monitor.nix`**

```nix
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
```

- [ ] **Step 2: Wire `deploy-monitor` into `home/scripts/default.nix`**

The `p.isDarwin` list now reads:

```nix
      ++ lib.optionals p.isDarwin [
        (pkgs.callPackage ./aws-evojam-mfa.nix {})
        (pkgs.callPackage ./gpush.nix {})
        (pkgs.callPackage ./deploy-monitor.nix {})
      ]
```

- [ ] **Step 3: Build the home activation package (proves it compiles + wires)**

Run: `nix build .#homeConfigurations.marcinwadon.activationPackage`
Expected: builds successfully; `./result/home-path/bin/deploy-monitor` exists.
Verify: `test -x ./result/home-path/bin/deploy-monitor && echo OK`

- [ ] **Step 4: Assert the collector-only plan via `--dry-run` (behavioral test)**

Run from the nix-config repo:
```bash
./result/home-path/bin/deploy-monitor --dry-run 2>&1
```
Expected output includes: a `bump claude-monitor (was …)` line, `ship flake.lock -> root@10.0.1.123:…`, `rebuild root@10.0.1.123 -> nixos-rebuild switch --flake .#monitor`, and `verify: GET http://10.0.1.123:8787/api/machines`. It must NOT contain any `root@10.0.1.120/121/122` line and must NOT contain `./switch home`. No ssh/rebuild/flake-update actually runs. `flake.lock` must remain unchanged (git status).

- [ ] **Step 5: Assert the fleet plan via `--dry-run`**

Run:
```bash
./result/home-path/bin/deploy-monitor --fleet --no-bump --dry-run 2>&1
```
Expected output includes: `skip bump (--no-bump)`, the box collector line (`.#monitor`), all three CT lines (`.#personal`, `.#evojam`, `.#parloa` at `.120/.121/.122`), and `deploy Mac host -> ./switch home`. No `bump claude-monitor` line. Nothing executes.

- [ ] **Step 6: Commit**

```bash
git add home/scripts/deploy-monitor.nix home/scripts/default.nix
git commit -m "feat(scripts): add deploy-monitor (bump+ship+rebuild claude-monitor fleet)"
```

---

## Self-Review

**Spec coverage:**
- gpush owner→account map, HTTPS-URL dodge, at-push-time token, `--user`/active fallback, `--force-with-lease` auto-pin, `--dry-run` → Task 1. ✓
- deploy-monitor guard, token-first capture, bump-then-deploy (default) + `--no-bump`, collector-always, `--fleet` CTs + Mac, verify, `--dry-run` → Task 2. ✓
- Packaging (writeShellScriptBin, `p.isDarwin`, absolute store paths, `let` constants) → both tasks. ✓
- Testing plan (nix build + dry-run) → Steps 3–5 of each task. ✓

**Placeholder scan:** No TBD/TODO; every step has full code or an exact command + expected output. ✓

**Type/name consistency:** `--dry-run`/`--fleet`/`--no-bump` flag names consistent; machine IPs and flake attrs match the Global Constraints table; owner→account map identical in spec and Task 1. `ship_lock`/`rebuild_remote` helper names consistent within Task 2. ✓

**Escaping note for the implementer:** the intricate bits are the Nix `''`-string escapes (`''${...}` for shell braces, literal `\"`/`\$` in the gpush credential helper). Step 3's `nix build` is the guard — a mis-escape fails evaluation there, before any commit.
