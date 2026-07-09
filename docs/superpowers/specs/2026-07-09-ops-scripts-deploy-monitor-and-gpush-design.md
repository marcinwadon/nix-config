# Design: two Mac-side ops scripts — `deploy-monitor` and `gpush`

Date: 2026-07-09
Repo: `marcinwadon/nix-config`
Status: approved (design), pending spec review → writing-plans

## Motivation

Two procedures recur verbatim across many sessions and currently live as
runbook text in the operator's memory (they are re-read every session):

1. **claude-monitor fleet deploy** — bump `flake.lock`, ship it to the monitor
   box (and optionally the 3 CTs + Mac host), rebuild. Appears in essentially
   every claude-monitor session. Mechanical, but footgun-prone (token capture
   order, which machines, serialized rebuild flags).
2. **git push with the correct GitHub account** — `origin` resolves to the
   wrong `gh` account on HTTPS-origin repos, and is Yubikey-gated on SSH-origin
   repos (parloa/evojam), so pushes are done via a hand-typed forced-token
   HTTPS incantation that differs per repo.

Both are deterministic → they should be code, not memory. Converting them lets
the memory hold *why*, not *the exact command*.

Scope is **Tier 1 only** (these two scripts). FOD-hash recompute and per-repo
git credential config were considered and deferred.

## Non-goals

- No auto-detection of collector-vs-fleet from the claude-monitor diff (flag
  chosen instead — see Decisions).
- No permanent git credential config (`includeIf`); it cannot dodge the
  Yubikey on SSH origins, so a wrapper is the complete solution.
- Not generalized to the CTs — both scripts are Darwin-gated (run from the Mac;
  their fleet topology + account map are Mac-specific).

## Shared conventions

- Each script is a `pkgs.writeShellScriptBin` derivation in `home/scripts/`,
  `pkgs.callPackage`'d into the `p.isDarwin` list in
  `home/scripts/default.nix` (same wiring/gating as `aws-evojam-mfa`).
- External tools are referenced by absolute Nix store path
  (`${pkgs.gh}/bin/gh`, `${pkgs.openssh}/bin/ssh`, `${pkgs.gnutar}/bin/tar`,
  `${pkgs.jq}/bin/jq`, `${pkgs.curl}/bin/curl`, `${pkgs.git}/bin/git`), so the
  scripts do not depend on ambient PATH.
- `set -euo pipefail` in every script.
- Both scripts take `--dry-run`: resolve and print the full plan (accounts,
  URLs, rebuild targets, ssh commands) **without executing** any
  side-effecting step. This is the primary test surface.
- Configuration constants (machine IPs, env names, owner→account map) live as
  `let` bindings at the top of each `.nix` file, mirroring how
  `aws-evojam-mfa.nix` holds its profile/ARN constants — easy to audit/change.

## Decisions (locked with the operator)

- **Deploy scope**: flag-driven. Default = collector-only (the common
  frontend/collector change); `--fleet` opts into the 4-host rebuild. Matches
  how the operator already reasons ("diff touched `cmd/host` → fleet").
- **Flake bump**: `deploy-monitor` runs `nix flake update claude-monitor` as
  its first step by default and leaves `flake.lock` **uncommitted** (the
  operator signs+commits nix-config `main` — Claude/scripts do not). `--no-bump`
  skips it for re-deploying an already-bumped lock.
- **Push fix**: a single wrapper command handling both SSH and HTTPS origins
  uniformly.

## Fleet topology (from operator memory)

| Machine  | Host            | Rebuild target                                    |
|----------|-----------------|---------------------------------------------------|
| box      | `root@10.0.1.123` | `nixos-rebuild switch --flake .#monitor` (collector) |
| personal | `root@10.0.1.120` | `nixos-rebuild switch --flake .#personal` (host)  |
| evojam   | `root@10.0.1.121` | `nixos-rebuild switch --flake .#evojam` (host)    |
| parloa   | `root@10.0.1.122` | `nixos-rebuild switch --flake .#parloa` (host)    |
| Mac      | local           | `./switch home` (host = launchd agent, restarted on activation) |

- CT login shell is fish → remote bash via `ssh root@ip "…bash -s"` heredocs.
- All remote rebuilds pass `--max-jobs 1 --cores 2` (avoid OOM-thrash on the
  LXCs, per the documented evojam OOM lesson).

---

## Script 1 — `deploy-monitor [--fleet] [--no-bump] [--dry-run]`

### Behavior

1. **Guard**: `toplevel=$(git rev-parse --show-toplevel)`; verify
   `flake.nix` under it declares the `claude-monitor` input (grep). Error and
   exit if not — the script must run from inside the nix-config repo, since it
   mutates that repo's `flake.lock` and rebuilds `--flake .#…`.
2. **Token**: `TOK=$(gh auth token)` captured into a variable **first** (bare
   returns the active account's token; active = `marcinwadon`, which holds
   private `claude-monitor` access). If empty → error. Never inlined into an
   `ssh` argument via `VAR=$(...) ssh …` (that assignment is invisible to
   argument expansion → empty token → auth failure).
3. **Bump** (skipped by `--no-bump`): record the current `claude-monitor`
   locked rev, run
   `NIX_CONFIG="access-tokens = github.com=$TOK" nix flake update claude-monitor`,
   then print `old-rev → new-rev`. `flake.lock` is left uncommitted.
4. **Collector deploy (always)**:
   - Ship: `cat flake.lock | ssh root@10.0.1.123 "cat > /root/nix-config/flake.lock"`.
   - Rebuild: `ssh root@10.0.1.123 "GHTOKEN='$TOK' bash -s"` with a heredoc that
     `export NIX_CONFIG="access-tokens = github.com=$GHTOKEN"`,
     `cd /root/nix-config`, and
     `nixos-rebuild switch --flake .#monitor --max-jobs 1 --cores 2`.
5. **Fleet deploy (only with `--fleet`)**:
   - For each CT `(personal .120, evojam .121, parloa .122)`: same ship +
     `nixos-rebuild switch --flake .#<env> --max-jobs 1 --cores 2`.
   - Mac host: run `./switch home` from the repo toplevel (reuses the repo's
     tested activation path; the Mac reads the working-tree `flake.lock`
     directly so no ship is needed).
6. **Verify**: `curl -s http://10.0.1.123:8787/api/machines | jq` and print
   which machines are connected (best-effort; a non-zero curl does not fail the
   deploy, only warns).

### `--dry-run`

Prints, without executing: whether it would bump (and current locked rev), the
collector target, and — if `--fleet` — every CT ship+rebuild command and the
Mac `./switch home` step. No ssh, no `nix flake update`, no rebuild.

### Notes / edge cases

- The token is passed to the box via a heredoc `GHTOKEN=...` env prefix on the
  `ssh` command, then re-exported into `NIX_CONFIG` remotely (the documented
  pattern). It is not placed in argv.
- Rebuild output streams to the terminal; the script fails (non-zero) if any
  remote `nixos-rebuild` fails, and reports which machine.
- This script does **not** recompute per-system FOD hashes (out of scope). A
  frontend-dependency change still requires the operator to recompute
  `pnpmDeps` hashes in the claude-monitor repo before the deploy; a failed box
  build with a hash mismatch will surface that.

---

## Script 2 — `gpush [extra-git-push-flags…] [--dry-run]`

### Behavior

1. **Parse origin**: `git remote get-url origin`; extract `OWNER/REPO` from both
   `git@github.com:OWNER/REPO(.git)` and `https://github.com/OWNER/REPO(.git)`.
   Error if origin is not a github.com remote.
2. **Map owner → account**:
   - `marcinwadon → marcinwadon`
   - `parloa → marcin-wadon-parloa`
   - `evojam → marcinwadon`
   - unknown → the active `gh` account, with a printed warning.
3. **Resolve HTTPS URL**: `https://github.com/OWNER/REPO.git` (an explicit HTTPS
   push URL dodges an SSH origin's Yubikey gate).
4. **Push** with a token resolved **at push time** inside a credential helper —
   so the token is never in argv/reflog:
   ```
   git -c credential.helper= \
       -c credential.helper="!f(){ echo username=<acct>; echo \"password=\$(gh auth token --user <acct> 2>/dev/null || gh auth token)\"; }; f" \
       push <HTTPS_URL> <refspec> <extra-flags>
   ```
   The `--user <acct>` first / bare-`gh auth token` fallback rule is validated:
   keyring accounts (`marcin-wadon-parloa`) resolve via `--user`; env-var/active
   accounts (`marcinwadon`) resolve via the bare fallback (their `--user` form
   fails).
5. **Default refspec**: current branch, `HEAD:$(git branch --show-current)`.
   Extra flags passed by the caller are appended.
6. **`--force-with-lease` auto-pin**: if the caller passes a bare
   `--force-with-lease` (no `=value`), expand it to
   `--force-with-lease=<branch>:<remote-sha>` where `remote-sha` comes from
   `git ls-remote <HTTPS_URL> <branch>`. This fixes the documented "stale info"
   rejection that occurs because the push goes to an ad-hoc URL rather than the
   tracked `origin` (whose lease ref is stale). An explicit
   `--force-with-lease=<value>` is passed through unchanged.

### `--dry-run`

Prints: parsed OWNER/REPO, chosen account, resolved HTTPS URL, the final
refspec, any auto-pinned `--force-with-lease` value, and the exact `git push`
command (with the token still resolved lazily, i.e. shown as the command
substitution, not the literal token). Does not push.

### Notes / edge cases

- Token safety: only the account *name* ever appears in argv; the token is
  produced by command substitution inside the helper at push time.
- If the mapped account is neither retrievable via `--user` nor the active
  account, the script errors clearly ("account <acct> not available in gh; run
  `gh auth login`") rather than pushing with the wrong identity.
- Only `origin` is consulted (matches every documented push). Pushing to other
  remotes is out of scope.

---

## Testing / verification plan

1. `nix flake check` and `nix build .#homeConfigurations.marcinwadon.activationPackage`
   — proves both derivations build and wire correctly.
2. `deploy-monitor --dry-run` and `deploy-monitor --fleet --dry-run` — confirm
   the printed plan matches the intended machines/targets.
3. `gpush --dry-run` run from a claude-monitor checkout, a parloa checkout, and
   an evojam checkout — confirm each resolves the correct account + HTTPS URL;
   `gpush --force-with-lease --dry-run` — confirm the lease is auto-pinned.
4. Real runs are the final confirmation (deploy a real claude-monitor bump;
   push a real branch), done by the operator.

## Files touched

- `home/scripts/deploy-monitor.nix` (new)
- `home/scripts/gpush.nix` (new)
- `home/scripts/default.nix` (wire both into the `p.isDarwin` list)
