# M1 Asahi Fleet Host Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the Mac mini M1 (`mini`, `10.0.1.91`, Fedora Asahi Remix 44 Server) to the claude-monitor fleet as three fully configured working hosts — `m1-personal`, `m1-evojam`, `m1-parloa`.

**Architecture:** Asahi stays; Nix + standalone home-manager provide the working environment (the Mac's `homeConfigurations` pattern). Three unix users give CT-style `$HOME` isolation, each running its own claude-monitor ACP host and tailer under a systemd user service. Secrets are plain files on the box (no sops); git signing keys are reused from the matching CT. Two PRs — a small claude-monitor slice (aarch64-linux support + `hatOf`) and the nix-config slice — then a bootstrap runbook.

**Tech Stack:** Nix flakes, home-manager (standalone), Go (claude-monitor), TypeScript + Vitest (dashboard), Fedora 44 / systemd 259.

Spec: `docs/superpowers/specs/2026-08-11-m1-asahi-fleet-host-design.md`

## Global Constraints

- **Two repos.** `claude-monitor` = `/Users/marcinwadon/Projects/marcinwadon/claude-monitor`. `nix-config` = `/Users/marcinwadon/Projects/marcinwadon/nix-config`.
- **Never push nix-config.** The operator commits and pushes that repo. Commit locally only.
- **The nix-config working tree contains the operator's unrelated uncommitted work**: `flake.lock`, `system/configuration-darwin.nix`, `system/pkgs/ghosthub.nix`. Never stage them. Always `git add <explicit paths>`, never `git add -A` or `git add .`.
- **Commits are signed** in both repos (Conventional Commits, `type(scope): subject`). If gpg pinentry hangs, commit with `--no-gpg-sign` and report it — do not silently skip.
- **All `.nix` files must pass `alejandra`** (nix-config's formatter): `nix run nixpkgs#alejandra -- <files>`.
- **Flakes ignore untracked files.** After creating any new file in a flake repo, run `git add -N <path>` before any `nix eval` / `nix build`, or evaluation cannot see it.
- **aarch64-linux can be evaluated on the Mac but only built on the M1.** The Mac is aarch64-darwin with no Linux builder. Use `nix eval` locally; run `nix build` over ssh on `marcin@10.0.1.91`.
- **The ACP adapter version stays pinned at `0.63.0`**, matching `claude-monitor/flake.nix`. Never `@latest`: the pin decides which model the dashboard's aliases resolve to.
- **Frontend commands must call binaries directly** — `./node_modules/.bin/vitest`, `./node_modules/.bin/tsc`. `pnpm exec` fails in this dev shell with `ERR_PNPM_IGNORED_BUILDS`.
- **Machine labels and users**, used verbatim everywhere: `m1-personal` / `marcin-personal`, `m1-evojam` / `marcin-evojam`, `m1-parloa` / `marcin-parloa`. Home directories are `/home/<username>`.
- **Git identity emails**, copied exactly from the existing CT profiles: personal `marcin.wadon@gmail.com`, evojam `mwadon@evojam.com`, parloa `244477798+marcin-wadon-parloa@users.noreply.github.com`.
- **Go/Nix commands on the Mac need the dev shell**: `nix develop 'path:.' --command bash -c '<cmd>'` from the repo root (`go` is not on PATH otherwise).

---

## File Structure

**claude-monitor (PR 1):**

| File | Responsibility |
|---|---|
| `frontend/src/lib/hats.ts` (modify) | `hasSegment` gains a separator argument; `hatOf` claims a client by machine-name segment as well as cwd segment |
| `frontend/src/lib/hats.test.ts` (modify) | Cases for `m1-*` labels, precedence, and non-regression of existing machines |
| `flake.nix` (modify) | `claude-agent-acp-modules.outputHash` gains its `aarch64-linux` entry |

**nix-config (PR 2):**

| File | Responsibility |
|---|---|
| `outputs/home-conf.nix` (modify) | `mkHome` takes `homeModules`; three `homeConfigurations.m1-*` added |
| `home/lib/profile-defaults.nix` (modify) | New `monitorTokenFile` option, defaulting to today's behaviour |
| `home/programs/claude-monitor-hook/default.nix` (modify) | Reads `monitorTokenFile` instead of hardcoding the sops path |
| `home/profiles/allowed_signers` (create) | Public signing keys for all identities — plaintext on purpose |
| `home/profiles/m1-common.nix` (create) | Shared M1 base; repoints all three inherited `/run/secrets/*` paths |
| `home/profiles/m1-{personal,evojam,parloa}.nix` (create) | One per identity: client name + email |
| `nixos/envs/monitor.nix` (modify) | Collector `WORKSPACE_ROOTS` gains the three `m1-*` machines |
| `flake.nix` (modify) | Secret-leak guard extended to cover the new Linux home configs |
| `docs/RUNBOOK-m1-asahi.md` (create) | Bootstrap steps, split by who can run them |

---

## Task 1: `hatOf` claims a client by machine-name segment

**Repo:** claude-monitor

**Files:**
- Modify: `frontend/src/lib/hats.ts:57-82`
- Test: `frontend/src/lib/hats.test.ts`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `hasSegment(value: string, seg: string, sep?: string): boolean` (third parameter defaults to `'/'`); `hatOf(s: Session): HatBucket` unchanged in signature.

**Why:** `hatOf` matches the machine name exactly, so `m1-parloa` would fall through to `personal`. The cwd clause cannot save it — CT repos live at `/home/marcin/Projects/<repo>` with no client segment.

- [ ] **Step 1: Write the failing tests**

Append to `frontend/src/lib/hats.test.ts`, inside the existing `describe('hatOf', …)` block, immediately before its closing `})`:

```ts
  it('claims an m1 client host by its machine-name segment', () => {
    expect(hatOf(mk({ machine: 'm1-parloa', cwd: '/home/marcin-parloa/Projects/platform-fe' }))).toBe('parloa')
    expect(hatOf(mk({ machine: 'm1-evojam', cwd: '/home/marcin-evojam/Projects/aws' }))).toBe('evojam')
  })
  it('puts the m1 personal host in personal', () => {
    expect(hatOf(mk({ machine: 'm1-personal', cwd: '/home/marcin-personal/Projects/claude-monitor' }))).toBe('personal')
  })
  it('prefers parloa when a parloa path sits on the m1 personal host', () => {
    expect(hatOf(mk({ machine: 'm1-personal', cwd: '/home/marcin-personal/Projects/parloa/x' }))).toBe('parloa')
  })
  it('does not let a hyphenated non-client machine claim a hat', () => {
    expect(hatOf(mk({ machine: 'm1-monitor', cwd: '' }))).toBe('personal')
  })
```

And append a new `describe` block at the end of the file:

```ts
describe('hasSegment with a custom separator', () => {
  it('splits a machine label on hyphens', () => {
    expect(hasSegment('m1-parloa', 'parloa', '-')).toBe(true)
  })
  it('still matches a bare machine name', () => {
    expect(hasSegment('parloa', 'parloa', '-')).toBe(true)
  })
  it('does not match a prefix of a hyphenated part', () => {
    expect(hasSegment('m1-parloainfra', 'parloa', '-')).toBe(false)
  })
  it('defaults to the path separator', () => {
    expect(hasSegment('/a/parloa/b', 'parloa')).toBe(true)
  })
})
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
cd /Users/marcinwadon/Projects/marcinwadon/claude-monitor/frontend
./node_modules/.bin/vitest run src/lib/hats.test.ts
```

Expected: FAIL. The `m1-parloa` / `m1-evojam` cases return `'personal'`, and `hasSegment('m1-parloa', 'parloa', '-')` returns `false` because the third argument is ignored.

- [ ] **Step 3: Generalise `hasSegment`**

In `frontend/src/lib/hats.ts`, replace the `hasSegment` function and its doc comment with:

```ts
/**
 * True when `value` contains a segment exactly equal to `seg`, splitting on
 * `sep`. Segment equality, not substring: `~/Projects/marcinwadon/parloa-infra`
 * must not be pulled into the Parloa hat, and neither must a machine named
 * `m1-parloainfra`.
 *
 * `sep` exists so the same rule applies to a machine label (`m1-parloa`, split
 * on `-`) as to a path — one predicate, two axes.
 */
export function hasSegment(value: string, seg: string, sep = '/'): boolean {
  return value.split(sep).includes(seg)
}
```

- [ ] **Step 4: Teach `hatOf` the machine-name axis**

In the same file, replace the `hatOf` function and its doc comment with:

```ts
/**
 * The single bucket a session belongs to.
 *
 * A client is claimed on two axes, in this order: the **machine label** (split
 * on `-`, so both `parloa` and `m1-parloa` match, and a bare `mac` does not),
 * then the **cwd** (split on `/`). The machine axis subsumes the old exact
 * match, and it exists because a client machine's repos need not sit under a
 * client-named path: on the CTs they live at /home/marcin/Projects/<repo>, which
 * is why only 45 of the 162 Parloa-scoped sessions live on the collector on
 * 2026-08-03 matched by machine at all.
 *
 * Clients are tested parloa-then-evojam, so a parloa path on a non-parloa
 * machine wins — the repo is the stronger signal. Concretely: a session on
 * `m1-personal` under ~/Projects/parloa buckets as parloa.
 *
 * Everything left over is `personal`, so the buckets are a total partition and
 * no session can disappear from every hat.
 */
export function hatOf(s: Session): HatBucket {
  const claims = (client: HatBucket): boolean =>
    hasSegment(s.machine, client, '-') || hasSegment(s.cwd, client)
  if (claims('parloa')) return 'parloa'
  if (claims('evojam')) return 'evojam'
  return 'personal'
}
```

- [ ] **Step 5: Run the full frontend suite and typecheck**

```bash
cd /Users/marcinwadon/Projects/marcinwadon/claude-monitor/frontend
./node_modules/.bin/vitest run
./node_modules/.bin/tsc --noEmit
```

Expected: all tests PASS (including the pre-existing `hatOf`, `filterByHat` and `HatSwitch` suites — the machine axis must not have changed any existing verdict), and `tsc` clean.

- [ ] **Step 6: Commit**

```bash
cd /Users/marcinwadon/Projects/marcinwadon/claude-monitor
git add frontend/src/lib/hats.ts frontend/src/lib/hats.test.ts
git commit -m "feat(hats): claim a client by machine-name segment

An m1-* client host would otherwise fall to the personal hat: hatOf
matched the machine name exactly, and the cwd clause does not save it
because a client machine's repos need not sit under a client-named path.
One predicate now covers both axes."
```

---

## Task 2: aarch64-linux FOD hash for the ACP adapter

**Repo:** claude-monitor

**Files:**
- Modify: `flake.nix:66-72` (the `claude-agent-acp-modules.outputHash` attrset)

**Interfaces:**
- Consumes: nothing.
- Produces: `packages.aarch64-linux.claude-agent-acp` evaluates and builds, which every later nix-config task depends on.

**Why:** the attrset is `{x86_64-linux; aarch64-darwin}.${system}`, so on aarch64-linux this is an **eval throw**, not a build failure — every Nix route is blocked until the third entry exists. A darwin build cannot produce the hash: the installed tree carries a platform-specific `@anthropic-ai/claude-agent-sdk-*`.

- [ ] **Step 1: Enable flakes for `marcin` on the M1**

```bash
ssh marcin@10.0.1.91 'mkdir -p ~/.config/nix && printf "experimental-features = nix-command flakes\n" > ~/.config/nix/nix.conf && nix flake --help >/dev/null && echo flakes-ok'
```

Expected: `flakes-ok`.

- [ ] **Step 2: Add a deliberately wrong hash so the build reports the real one**

In `claude-monitor/flake.nix`, inside the `outputHash = { … }.${system};` attrset, add the `aarch64-linux` line so it reads:

```nix
          outputHash = {
            x86_64-linux = "sha256-f7M+j96rRO0sy0Mhf1p1OiEoxYx5FPA1gOUOhlxvVsE=";
            aarch64-darwin = "sha256-PNtSyahjiTYmtyxEw5IdGyofoEZbljBr09poOgy+ePc=";
            aarch64-linux = pkgs.lib.fakeHash;
          }.${system};
```

- [ ] **Step 3: Copy the working tree to the M1 and build to harvest the hash**

The repo is private, so a `github:` fetch would need a token; tar-pipe instead. `path:` makes nix read the working tree rather than the last commit.

```bash
cd /Users/marcinwadon/Projects/marcinwadon/claude-monitor
ssh marcin@10.0.1.91 'rm -rf ~/cm-src && mkdir -p ~/cm-src'
COPYFILE_DISABLE=1 tar czf - --exclude .git --exclude node_modules --exclude result . \
  | ssh marcin@10.0.1.91 'tar xzf - -C ~/cm-src'
ssh marcin@10.0.1.91 'cd ~/cm-src && nix build "path:.#claude-agent-acp" 2>&1 | tail -6'
```

Expected: a hash mismatch naming the real value, e.g.

```
error: hash mismatch in fixed-output derivation '/nix/store/...-claude-agent-acp-modules-0.63.0.drv':
         specified: sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
            got:    sha256-<THE REAL VALUE>
```

Record the `got:` value.

- [ ] **Step 4: Replace `fakeHash` with the harvested value**

Edit the same line, substituting the recorded hash:

```nix
            aarch64-linux = "sha256-<THE REAL VALUE>";
```

Also extend the comment directly above the attrset (currently ending "…aarch64-darwin is for local builds.") by appending one sentence:

```
          # aarch64-linux is the M1 Asahi host; its hash must be computed on that
          # box (a darwin build produces a different tree).
```

- [ ] **Step 5: Re-ship and prove the build succeeds and the adapter runs**

```bash
cd /Users/marcinwadon/Projects/marcinwadon/claude-monitor
COPYFILE_DISABLE=1 tar czf - --exclude .git --exclude node_modules --exclude result . \
  | ssh marcin@10.0.1.91 'rm -rf ~/cm-src && mkdir -p ~/cm-src && tar xzf - -C ~/cm-src'
ssh marcin@10.0.1.91 'cd ~/cm-src && nix build "path:.#claude-agent-acp" && \
  printf "%s\n" "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":1,\"clientCapabilities\":{}}}" \
  | timeout 25 ./result/bin/claude-agent-acp | head -c 200'
```

Expected: the build succeeds and the adapter answers with `"protocolVersion":1`. A successful build alone is not enough — it proves the hash, not that the binary runs on a 16K-page kernel.

- [ ] **Step 6: Verify the hook package builds too**

```bash
ssh marcin@10.0.1.91 'cd ~/cm-src && nix build "path:.#claude-monitor-hook" && ls result/bin'
```

Expected: `claude-monitor-cm-acp  claude-monitor-hook  claude-monitor-host  claude-monitor-tail`. This is the package the M1 profiles install, and it confirms the Go build works on aarch64-linux without the frontend FOD being forced.

- [ ] **Step 7: Commit**

```bash
cd /Users/marcinwadon/Projects/marcinwadon/claude-monitor
git add flake.nix
git commit -m "build: add the aarch64-linux adapter FOD hash

The outputHash attrset had no aarch64-linux entry, which is an eval
throw rather than a build failure, so the M1 Asahi host could not
evaluate at all. Computed on that box: the installed tree carries a
platform-specific claude-agent-sdk, so a darwin build cannot produce it."
```

---

## Task 3: `mkHome` takes `homeModules`

**Repo:** nix-config

**Files:**
- Modify: `outputs/home-conf.nix:48-60`

**Interfaces:**
- Consumes: nothing.
- Produces: `mkHome { system, profile, homeModules ? [] }`. Task 5 calls it with `homeModules = []` for the three M1 configs.

**Why:** `mkHome` imports `neovim-flake.homeManagerModules.${system}` unconditionally. On aarch64-linux that would try to source-build neovim, which the repo's own comment rules out ("crates.io blocks the pinned old nixpkgs's cargo-vendor User-Agent"). `outputs/nixos-conf.nix` already passes `homeModules = []` for exactly this reason — this unifies an existing pattern.

- [ ] **Step 1: Record the current darwin drvPath as the regression baseline**

This refactor must be behaviour-preserving for the Mac. Capture the derivation hash before touching anything:

```bash
cd /Users/marcinwadon/Projects/marcinwadon/nix-config
nix eval --raw .#homeConfigurations.marcinwadon.activationPackage.drvPath | tee /tmp/m1-plan-darwin-before.txt
```

- [ ] **Step 2: Add the parameter**

In `outputs/home-conf.nix`, replace the `mkHome` definition:

```nix
  mkHome = {
    system,
    profile,
    homeModules ? [inputs.neovim-flake.homeManagerModules.${system}.default],
  }:
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = mkPkgs system;
      extraSpecialArgs = {inherit profile;};
      modules = homeModules ++ [../home/home.nix];
    };
```

The default reproduces today's behaviour exactly, so the Darwin config needs no change. Linux callers pass `homeModules = []`.

- [ ] **Step 3: Prove the darwin config is byte-identical**

```bash
cd /Users/marcinwadon/Projects/marcinwadon/nix-config
nix eval --raw .#homeConfigurations.marcinwadon.activationPackage.drvPath > /tmp/m1-plan-darwin-after.txt
diff /tmp/m1-plan-darwin-before.txt /tmp/m1-plan-darwin-after.txt && echo "IDENTICAL"
```

Expected: `IDENTICAL`. If the drvPaths differ, the refactor changed behaviour — stop and fix it rather than accepting the diff.

- [ ] **Step 4: Prove the NixOS configs still evaluate**

```bash
cd /Users/marcinwadon/Projects/marcinwadon/nix-config
for e in personal evojam parloa monitor; do
  printf "%s " "$e"
  nix eval --raw ".#nixosConfigurations.$e.config.system.build.toplevel.drvPath" >/dev/null && echo ok
done
```

Expected: `personal ok`, `evojam ok`, `parloa ok`, `monitor ok`.

- [ ] **Step 5: Format and commit**

```bash
cd /Users/marcinwadon/Projects/marcinwadon/nix-config
nix run nixpkgs#alejandra -- outputs/home-conf.nix
git add outputs/home-conf.nix
git commit -m "refactor(home): let mkHome take its home-manager modules

The neovim-flake module is Darwin-only and was imported unconditionally,
so a Linux homeConfiguration could not use mkHome. The default keeps the
Darwin config byte-identical (verified by drvPath); nixos-conf already
passed an empty module list for the same reason."
```

---

## Task 4: `monitorTokenFile` becomes a profile value

**Repo:** nix-config

**Files:**
- Modify: `home/lib/profile-defaults.nix:46-56`
- Modify: `home/programs/claude-monitor-hook/default.nix:20-31`

**Interfaces:**
- Consumes: nothing.
- Produces: profile key `monitorTokenFile` — `null` means "derive today's default"; a string is used verbatim. Task 5's M1 profiles set it.

**Why:** the hook module hardcodes `/run/secrets/monitor_token` for all of Linux. That path does not exist on Fedora, and the wrapper does `[ -r "$f" ] && export MONITOR_TOKEN=…`, so a missing file leaves the variable silently unset and the host simply never registers.

- [ ] **Step 1: Record baselines for one Linux and one darwin config**

```bash
cd /Users/marcinwadon/Projects/marcinwadon/nix-config
nix eval --raw .#homeConfigurations.marcinwadon.activationPackage.drvPath > /tmp/m1-plan-t4-darwin-before.txt
nix eval --raw .#nixosConfigurations.parloa.config.system.build.toplevel.drvPath > /tmp/m1-plan-t4-parloa-before.txt
```

- [ ] **Step 2: Add the option**

In `home/lib/profile-defaults.nix`, directly after the `monitorUrl` line, add:

```nix
  # Absolute path the hook/tailer/host wrappers read MONITOR_TOKEN from at
  # runtime. null = derive the platform default (sops on NixOS, ~/.config on
  # darwin). Set it explicitly on a Linux box that has no sops-nix — otherwise
  # the token file is unreadable, MONITOR_TOKEN stays unset, and the host
  # silently never registers with the collector.
  monitorTokenFile = null;
```

- [ ] **Step 3: Consume it in the hook module**

In `home/programs/claude-monitor-hook/default.nix`, replace the `tokenFile` binding:

```nix
  tokenFile =
    if p.monitorTokenFile != null
    then p.monitorTokenFile
    else if pkgs.stdenv.isLinux
    then "/run/secrets/monitor_token"
    else "${config.home.homeDirectory}/.config/claude-monitor/token";
```

- [ ] **Step 4: Prove nothing existing changed**

```bash
cd /Users/marcinwadon/Projects/marcinwadon/nix-config
nix eval --raw .#homeConfigurations.marcinwadon.activationPackage.drvPath > /tmp/m1-plan-t4-darwin-after.txt
nix eval --raw .#nixosConfigurations.parloa.config.system.build.toplevel.drvPath > /tmp/m1-plan-t4-parloa-after.txt
diff /tmp/m1-plan-t4-darwin-before.txt /tmp/m1-plan-t4-darwin-after.txt && echo "DARWIN IDENTICAL"
diff /tmp/m1-plan-t4-parloa-before.txt /tmp/m1-plan-t4-parloa-after.txt && echo "PARLOA IDENTICAL"
```

Expected: both `IDENTICAL`. The default must be a pure no-op for every existing machine.

- [ ] **Step 5: Format and commit**

```bash
cd /Users/marcinwadon/Projects/marcinwadon/nix-config
nix run nixpkgs#alejandra -- home/lib/profile-defaults.nix home/programs/claude-monitor-hook/default.nix
git add home/lib/profile-defaults.nix home/programs/claude-monitor-hook/default.nix
git commit -m "feat(monitor): make the hook token path a profile value

A Linux box without sops-nix had no way to point the wrappers at a
readable token, and the failure is silent: the wrapper only exports
MONITOR_TOKEN if the file is readable, so the host never registers.
Default derives today's behaviour, verified by unchanged drvPaths."
```

---

## Task 5: The three M1 profiles and home configurations

**Repo:** nix-config

**Files:**
- Create: `home/profiles/allowed_signers`
- Create: `home/profiles/m1-common.nix`
- Create: `home/profiles/m1-personal.nix`, `home/profiles/m1-evojam.nix`, `home/profiles/m1-parloa.nix`
- Modify: `outputs/home-conf.nix` (add the three `homeConfigurations`)
- Modify: `flake.nix` (extend the secret-leak check)

**Interfaces:**
- Consumes: `mkHome { …, homeModules }` (Task 3); `monitorTokenFile` (Task 4); `packages.aarch64-linux.claude-monitor-hook` and `.claude-agent-acp` (Task 2).
- Produces: `homeConfigurations.m1-personal`, `.m1-evojam`, `.m1-parloa`, each an aarch64-linux activation package.

**Why:** `home/profiles/common.nix` hardcodes **three** absolute `/run/secrets/*` paths — `sshMatchBlocks."github.com".identityFile`, `git.signing.key`, `git.signing.allowedSignersFile`. Inheriting any of them leaves a box that cannot push (surfacing only at the first `git push`) or cannot sign. This is the one place in the plan where a mistake fails silently, so Step 6 asserts the rendered values rather than trusting a successful build.

- [ ] **Step 1: Build the plaintext `allowed_signers` from the three CTs**

These are **public** keys, so they belong in the repo in the clear. Take the union of what the three CTs already trust, so every identity can verify the others' commits:

```bash
cd /Users/marcinwadon/Projects/marcinwadon/nix-config
for ip in 10.0.1.120 10.0.1.121 10.0.1.122; do
  ssh marcin@$ip 'cat /run/secrets/allowed_signers'
done | sort -u > home/profiles/allowed_signers
printf "\n=== resulting file ===\n"; cat home/profiles/allowed_signers
```

Expected: one line per identity, each `<principal> <keytype> <key>`. Confirm there are at least three distinct lines and no line contains a PRIVATE KEY header. If any CT is unreachable, stop — do not invent an entry.

Prepend a comment line so the file explains itself:

```bash
cd /Users/marcinwadon/Projects/marcinwadon/nix-config
printf '# Public ssh signing keys, per identity. Public key material by\n# definition, so this is deliberately NOT a sops secret. Consumed by the\n# m1-* profiles via git.extraGitconfigFiles; the CTs still read their own\n# copies from sops.\n%s' "$(cat home/profiles/allowed_signers)" > /tmp/as.new && mv /tmp/as.new home/profiles/allowed_signers
```

- [ ] **Step 2: Create `home/profiles/m1-common.nix`**

```nix
# Shared base for the three Mac mini M1 users (Fedora Asahi Remix, no NixOS).
#
# A function of the identity so every per-user path is derived once. Called by
# home/profiles/m1-<client>.nix.
#
# CRITICAL: common.nix — the shared Linux base — hardcodes three absolute
# /run/secrets/* paths that DO NOT EXIST on this box, because there is no
# sops-nix here. All three are overridden below. Missing them fails silently:
# a wrong identityFile surfaces only at the first `git push`, and a wrong
# signing key only at the first commit.
{
  client,
  email,
}: let
  common = import ./common.nix;
  username = "marcin-${client}";
  home = "/home/${username}";
  signingKey = "${home}/.ssh/id_ed25519_signing";
  allowedSigners = "${home}/.config/git/allowed_signers";
in
  common
  // {
    inherit username;

    # Dashboard label. Fleet-unique: the collector keys host connections by
    # machine name and closes the previous one, so reusing a CT's label would
    # make the two evict each other in a loop.
    monitorMachine = "m1-${client}";

    # No sops on this box; the token is a plain 0600 file placed at bootstrap.
    monitorTokenFile = "${home}/.config/claude-monitor/token";

    # Override 1 of 3. Also the GitHub auth identity, not just signing.
    sshMatchBlocks = {
      "github.com" = {
        identityFile = signingKey;
        identitiesOnly = true;
      };
    };

    git =
      common.git
      // {
        userEmail = email;
        # Overrides 2 and 3.
        signing =
          common.git.signing
          // {
            key = signingKey;
            allowedSignersFile = allowedSigners;
          };
        # Delivers the repo's plaintext allowed_signers to the path above.
        extraGitconfigFiles = {
          "allowed_signers" = builtins.readFile ./allowed_signers;
        };
      };
  }
```

- [ ] **Step 3: Create the three per-identity profiles**

`home/profiles/m1-personal.nix`:

```nix
import ./m1-common.nix {
  client = "personal";
  email = "marcin.wadon@gmail.com";
}
```

`home/profiles/m1-evojam.nix`:

```nix
import ./m1-common.nix {
  client = "evojam";
  email = "mwadon@evojam.com";
}
```

`home/profiles/m1-parloa.nix`:

```nix
import ./m1-common.nix {
  client = "parloa";
  email = "244477798+marcin-wadon-parloa@users.noreply.github.com";
}
```

- [ ] **Step 4: Register the three home configurations**

In `outputs/home-conf.nix`, replace the final attrset so it reads:

```nix
in {
  # Exposed builders so the NixOS layer can reuse the same module set.
  inherit mkHome mkPkgs mkOverlays;

  # Darwin standalone home configuration (unchanged behavior).
  homeConfigurations.marcinwadon = mkHome {
    system = "aarch64-darwin";
    profile = import ../home/profiles/darwin.nix;
  };

  # Mac mini M1 (Fedora Asahi Remix) — three standalone users, one per client
  # identity. homeModules = [] because neovim-flake is Darwin-only.
  homeConfigurations.m1-personal = mkHome {
    system = "aarch64-linux";
    profile = import ../home/profiles/m1-personal.nix;
    homeModules = [];
  };
  homeConfigurations.m1-evojam = mkHome {
    system = "aarch64-linux";
    profile = import ../home/profiles/m1-evojam.nix;
    homeModules = [];
  };
  homeConfigurations.m1-parloa = mkHome {
    system = "aarch64-linux";
    profile = import ../home/profiles/m1-parloa.nix;
    homeModules = [];
  };
}
```

- [ ] **Step 5: Make the new files visible to the flake, then evaluate**

Flakes ignore untracked files, so evaluation cannot see them until they are at least intent-added:

```bash
cd /Users/marcinwadon/Projects/marcinwadon/nix-config
git add -N home/profiles/allowed_signers home/profiles/m1-common.nix \
  home/profiles/m1-personal.nix home/profiles/m1-evojam.nix home/profiles/m1-parloa.nix
for c in m1-personal m1-evojam m1-parloa; do
  printf "%s " "$c"
  nix eval --raw ".#homeConfigurations.$c.activationPackage.drvPath" >/dev/null && echo ok
done
```

Expected: `m1-personal ok`, `m1-evojam ok`, `m1-parloa ok`.

- [ ] **Step 6: Assert the three sops paths are actually gone**

This is the discriminating check. A successful evaluation proves nothing here — an inherited sops path evaluates perfectly and only fails at runtime.

```bash
cd /Users/marcinwadon/Projects/marcinwadon/nix-config
for c in personal evojam parloa; do
  echo "--- m1-$c ---"
  nix eval --raw ".#homeConfigurations.m1-$c.config.programs.git.settings.user.signingkey"
  echo ""
  nix eval --raw ".#homeConfigurations.m1-$c.config.programs.git.settings.gpg.ssh.allowedSignersFile"
  echo ""
  nix eval --raw ".#homeConfigurations.m1-$c.config.programs.ssh.matchBlocks.\"github.com\".identityFile"
  echo ""
done
```

Expected, for each client, exactly:

```
/home/marcin-<client>/.ssh/id_ed25519_signing
/home/marcin-<client>/.config/git/allowed_signers
/home/marcin-<client>/.ssh/id_ed25519_signing
```

Any `/run/secrets/...` in this output is a failure. Then confirm no sops path survives anywhere in a rendered config:

```bash
cd /Users/marcinwadon/Projects/marcinwadon/nix-config
for c in m1-personal m1-evojam m1-parloa; do
  printf "%s: " "$c"
  if nix eval --json ".#homeConfigurations.$c.config.programs.git.settings" | grep -q '/run/secrets'; then
    echo "FAIL — sops path leaked"
  else
    echo "clean"
  fi
done
```

Expected: three `clean`.

- [ ] **Step 7: Confirm the monitor wiring resolved to this machine**

```bash
cd /Users/marcinwadon/Projects/marcinwadon/nix-config
nix eval --raw '.#homeConfigurations.m1-parloa.config.systemd.user.services.claude-monitor-host.Service.ExecStart' \
  | xargs cat | grep -E 'MONITOR_MACHINE|MONITOR_TOKEN|CLAUDE_ACP_CMD'
```

Expected: `MONITOR_MACHINE="m1-parloa"`, a `MONITOR_TOKEN` read from `/home/marcin-parloa/.config/claude-monitor/token`, and a `CLAUDE_ACP_CMD` pointing into `/nix/store/...claude-agent-acp...`. This also proves the systemd-user branch (not the launchd one) was selected.

- [ ] **Step 8: Extend the secret-leak guard to the new Linux configs**

`flake.nix`'s `no-linux-secret-leak` check only walks `nixosConfigurations`. The M1 is a new Linux machine and deserves the same guard. In `flake.nix`, replace the `rendered` binding inside that check with:

```nix
      renderFish = f: (f.shellInit or "") + "\n" + (f.interactiveShellInit or "");
      rendered =
        lib.concatMapStringsSep "\n" (e:
          renderFish self.nixosConfigurations.${e}.config.home-manager.users.marcin.programs.fish)
        ["personal" "evojam" "parloa" "monitor"]
        + "\n"
        + lib.concatMapStringsSep "\n" (c:
          renderFish self.homeConfigurations.${c}.config.programs.fish)
        ["m1-personal" "m1-evojam" "m1-parloa"];
```

- [ ] **Step 9: Run the guard and format**

```bash
cd /Users/marcinwadon/Projects/marcinwadon/nix-config
nix build .#checks.aarch64-darwin.no-linux-secret-leak && echo "GUARD PASSES"
nix run nixpkgs#alejandra -- flake.nix outputs/home-conf.nix home/profiles/m1-common.nix \
  home/profiles/m1-personal.nix home/profiles/m1-evojam.nix home/profiles/m1-parloa.nix
```

Expected: `GUARD PASSES`, and alejandra reports no remaining changes on a second run.

- [ ] **Step 10: Commit**

```bash
cd /Users/marcinwadon/Projects/marcinwadon/nix-config
git add home/profiles/allowed_signers home/profiles/m1-common.nix \
  home/profiles/m1-personal.nix home/profiles/m1-evojam.nix home/profiles/m1-parloa.nix \
  outputs/home-conf.nix flake.nix
git commit -m "feat(m1): three home configurations for the Asahi Mac mini

One user per client identity, CT-style isolation, on aarch64-linux.
m1-common repoints all three of common.nix's absolute /run/secrets
paths: this box has no sops-nix, and an inherited path is a silent
failure that surfaces only at the first push or commit. allowed_signers
becomes a plaintext repo file — it is public key material. The
secret-leak guard now covers these configs too."
```

---

## Task 6: Collector `WORKSPACE_ROOTS` learns the three machines

**Repo:** nix-config

**Files:**
- Modify: `nixos/envs/monitor.nix:54`

**Interfaces:**
- Consumes: the machine labels from Task 5.
- Produces: a collector that enumerates projects for the three M1 hosts.

**Why:** a machine absent from `WORKSPACE_ROOTS` enumerates `[]` and the endpoint still returns 200 — the project picker is **silently empty**, not broken.

- [ ] **Step 1: Append the three machines**

In `nixos/envs/monitor.nix`, replace the collector's `WORKSPACE_ROOTS` export (line 54) with:

```nix
        export WORKSPACE_ROOTS="mac=/Users/marcinwadon/Projects/parloa,/Users/marcinwadon/Projects/marcinwadon,/Users/marcinwadon/Projects/evojam;personal=/home/marcin/Projects;evojam=/home/marcin/Projects;parloa=/home/marcin/Projects;m1-personal=/home/marcin-personal/Projects;m1-evojam=/home/marcin-evojam/Projects;m1-parloa=/home/marcin-parloa/Projects"
```

- [ ] **Step 2: Prove the rendered start script carries them**

```bash
cd /Users/marcinwadon/Projects/marcinwadon/nix-config
nix eval --raw '.#nixosConfigurations.monitor.config.systemd.services.claude-monitor.serviceConfig.ExecStart' \
  | xargs cat | grep -o 'm1-[a-z]*=[^;"]*'
```

Expected exactly three lines:

```
m1-personal=/home/marcin-personal/Projects
m1-evojam=/home/marcin-evojam/Projects
m1-parloa=/home/marcin-parloa/Projects
```

- [ ] **Step 3: Format and commit**

```bash
cd /Users/marcinwadon/Projects/marcinwadon/nix-config
nix run nixpkgs#alejandra -- nixos/envs/monitor.nix
git add nixos/envs/monitor.nix
git commit -m "feat(monitor): workspace roots for the three m1 hosts

A machine missing from WORKSPACE_ROOTS enumerates an empty list and the
endpoint still returns 200, so the project picker would be silently
empty rather than visibly broken."
```

---

## Task 7: Bootstrap runbook

**Repo:** nix-config

**Files:**
- Create: `docs/RUNBOOK-m1-asahi.md`

**Interfaces:**
- Consumes: everything above.
- Produces: the document Task 8 executes.

**Why:** `sudo` needs a password on this box, so roughly half the bootstrap cannot be automated. Splitting by *who can run it* is the whole point of the document.

- [ ] **Step 1: Write the runbook**

Create `docs/RUNBOOK-m1-asahi.md` with exactly this content:

````markdown
# RUNBOOK — Mac mini M1 (Fedora Asahi Remix) fleet host

`mini` · `10.0.1.91` · Fedora Asahi Remix 44 Server · aarch64, **16K pages** ·
SELinux **enforcing** · users `marcin-{personal,evojam,parloa}` · dashboard
labels `m1-{personal,evojam,parloa}`.

Design: `docs/superpowers/specs/2026-08-11-m1-asahi-fleet-host-design.md`

## Facts that decide the procedure

- **Install Nix with `dnf`, never the nixos.org script** — the legacy installer
  deliberately aborts under SELinux enforcing. Fedora 44 packages Nix.
- **The 16K kernel is fine.** The 4K-built nixpkgs cache runs here, including
  node/V8 with JIT and the ACP adapter's prebuilt linux-arm64 SDK. `kernel`
  (4K) exists at the same version as `kernel-16k` and is a pure fallback; do
  not switch without a measured failure.
- **`nix-ld` is not needed.** Fedora is an ordinary glibc distribution, so
  `pkgs.claude-code` works directly. No native `~/.local/bin` install.
- **Signing keys are reused from the matching CT** — one key per client
  *identity*, not per machine. The key also serves GitHub authentication.

## Step 1 — operator, as root (cannot be automated: sudo needs a password)

```bash
sudo dnf install -y nix
sudo systemctl enable --now nix-daemon

# One user per client identity.
for c in personal evojam parloa; do
  sudo useradd -m -s /bin/bash "marcin-$c"
done

# systemd user services must survive logout. Without this the ACP host runs
# only while an ssh session is open. The CTs get this from
# users.users.marcin.linger in nixos/lxc-base.nix, which does not exist here.
for c in personal evojam parloa; do
  sudo loginctl enable-linger "marcin-$c"
done

# Reuse marcin's authorized_keys so the fleet can reach each user.
for c in personal evojam parloa; do
  sudo install -d -m 700 -o "marcin-$c" -g "marcin-$c" "/home/marcin-$c/.ssh"
  sudo cp /home/marcin/.ssh/authorized_keys "/home/marcin-$c/.ssh/authorized_keys"
  sudo chown "marcin-$c:marcin-$c" "/home/marcin-$c/.ssh/authorized_keys"
  sudo chmod 600 "/home/marcin-$c/.ssh/authorized_keys"
done
```

Verify: `loginctl show-user marcin-parloa | grep Linger` prints `Linger=yes`,
and `ssh marcin-parloa@10.0.1.91 true` succeeds from the Mac.

## Step 2 — automatable, per user

Run for each `c` in `personal evojam parloa`, as `marcin-$c`:

```bash
# Flakes.
mkdir -p ~/.config/nix
printf "experimental-features = nix-command flakes\n" > ~/.config/nix/nix.conf

# Monitor token (shared fleet-wide), 0600.
mkdir -p ~/.config/claude-monitor
# Copy the value from an existing CT: ssh marcin@10.0.1.121 'cat /run/secrets/monitor_token'
install -m 600 /dev/stdin ~/.config/claude-monitor/token <<< "$TOKEN"

# Signing key, reused from the matching CT (personal .120, evojam .121, parloa .122).
mkdir -p ~/.ssh && chmod 700 ~/.ssh
install -m 600 /dev/stdin ~/.ssh/id_ed25519_signing <<< "$KEY"

# Activate.
nix run home-manager/master -- switch --flake "path:/home/marcin/nix-config#m1-$c"
```

The flake source must be readable by all three users; keep the checkout at
`/home/marcin/nix-config` (mode 755) rather than inside one user's home.

## Step 3 — operator, interactive, once per user (cannot be scripted)

```bash
ssh -t "marcin-$c@10.0.1.91" 'claude /login'
```

Until this is done, `session/prompt` fails with
`-32000 "Authentication required"`, which reads like a code bug and is not one.

## Step 4 — collector

Deploy the `WORKSPACE_ROOTS` change and restart the collector on the monitor box
(`10.0.1.123`). Without it the project picker for the M1 hosts is silently empty.

## Verification (all four must pass)

1. `curl -s http://10.0.1.123:8787/api/machines` lists `m1-personal`,
   `m1-evojam`, `m1-parloa` alongside the existing four.
2. `curl -s http://10.0.1.123:8787/api/machines/m1-parloa/projects` returns a
   non-empty list.
3. Start a session on `m1-parloa` from the dashboard, send a prompt, get a reply.
4. That session appears under the **Parloa** hat, not Personal.

## Maintenance notes

- Three home-manager generations. A shared-module change needs three `switch`
  runs on this box, not one.
- Kernel updates come from Asahi, outside git. If a *new* dependency could bake
  page size at build time, re-probe rather than assume — see the probe set in
  the design document.
- Nix itself is Fedora-packaged, so `dnf upgrade` moves it. Unusual for this
  fleet; the CTs pin Nix through NixOS.
````

- [ ] **Step 2: Commit**

```bash
cd /Users/marcinwadon/Projects/marcinwadon/nix-config
git add docs/RUNBOOK-m1-asahi.md
git commit -m "docs(m1): bootstrap runbook for the Asahi Mac mini

Split by who can run each step: sudo needs a password on this box, so
the root half and the three claude /login steps are the operator's."
```

---

## Task 8: Execute the bootstrap and verify end to end

**Repo:** none (operational)

**Files:** none.

**Interfaces:**
- Consumes: Tasks 1–7.
- Produces: three registered hosts, verified from the collector's own API.

**Why:** every earlier task verified an artifact. This one verifies the *system*. A green build proves nothing about a host that never registers.

- [ ] **Step 1: Ask the operator to run Step 1 of the runbook**

Print the exact block from `docs/RUNBOOK-m1-asahi.md` Step 1 and wait. It cannot be automated: `sudo` requires a password.

- [ ] **Step 2: Confirm the prerequisites landed**

```bash
for c in personal evojam parloa; do
  printf "marcin-%s: " "$c"
  ssh -o ConnectTimeout=5 -o BatchMode=yes "marcin-$c@10.0.1.91" 'echo ssh-ok' 2>&1 | tr -d '\n'
  ssh marcin@10.0.1.91 "loginctl show-user marcin-$c 2>/dev/null | grep -o 'Linger=yes'" 2>&1
done
```

Expected, per user: `ssh-ok` and `Linger=yes`. Do not proceed on a `Linger=no` — the host would vanish at logout and the failure would look intermittent.

- [ ] **Step 3: Place the flake checkout where all three users can read it**

```bash
cd /Users/marcinwadon/Projects/marcinwadon/nix-config
ssh marcin@10.0.1.91 'sudo mkdir -p /srv/nix-config && sudo chown marcin:marcin /srv/nix-config && sudo chmod 755 /srv/nix-config'
COPYFILE_DISABLE=1 tar czf - --exclude .git --exclude result . \
  | ssh marcin@10.0.1.91 'tar xzf - -C /srv/nix-config'
ssh marcin@10.0.1.91 'ls /srv/nix-config/home/profiles/m1-common.nix && echo staged-ok'
```

Note: the tar carries the working tree, so the `git add -N` visibility problem does not apply — but `path:` must be used as the flake ref, since there is no `.git` on the box. The checkout lives at `/srv/nix-config`, NOT inside `/home/marcin` — that directory is mode `700`, so a checkout there would be unreadable by the other two users (`EACCES` on their `path:` flake ref, which reads like a nix problem and is not one). See the runbook's "Facts that decide the procedure" for the full reasoning.

- [ ] **Step 4: Place the token and signing key for each user**

```bash
TOKEN=$(ssh marcin@10.0.1.121 'cat /run/secrets/monitor_token')
declare -A CT=([personal]=10.0.1.120 [evojam]=10.0.1.121 [parloa]=10.0.1.122)
for c in personal evojam parloa; do
  KEY=$(ssh "marcin@${CT[$c]}" 'cat /run/secrets/ssh_signing_key')
  ssh "marcin-$c@10.0.1.91" "mkdir -p ~/.config/claude-monitor ~/.ssh && chmod 700 ~/.ssh \
    && install -m 600 /dev/stdin ~/.config/claude-monitor/token <<< '$TOKEN' \
    && install -m 600 /dev/stdin ~/.ssh/id_ed25519_signing <<< '$KEY' \
    && mkdir -p ~/.config/nix && printf 'experimental-features = nix-command flakes\n' > ~/.config/nix/nix.conf \
    && ls -l ~/.config/claude-monitor/token ~/.ssh/id_ed25519_signing"
done
```

Expected: both files at mode `600` for all three users. Verify the key is usable rather than merely present:

```bash
for c in personal evojam parloa; do
  printf "marcin-%s: " "$c"
  ssh "marcin-$c@10.0.1.91" 'ssh-keygen -y -f ~/.ssh/id_ed25519_signing >/dev/null && echo key-valid'
done
```

- [ ] **Step 5: Activate each home configuration**

```bash
for c in personal evojam parloa; do
  echo "=== m1-$c ==="
  ssh "marcin-$c@10.0.1.91" "nix build 'path:/srv/nix-config#homeConfigurations.m1-$c.activationPackage' && ./result/activate 2>&1 | tail -5"
done
```

Uses the pinned home-manager revision from `flake.lock` via
`homeConfigurations.m1-$c.activationPackage`, not the registry's unpinned
`home-manager/master` — the runbook's Step 3 settled on this form so the
activating CLI version can never drift from the configuration it activates;
this step must match it.

Expected: `Activating …` lines ending without error for each. This is the first real aarch64-linux *build*, so expect it to take a while on the first user and be largely cached for the next two.

- [ ] **Step 6: Configure the fish shell for each user**

Fish is installed by home-manager, so it does not exist until Step 5's activation has run — this step must come after Step 5, not before, matching the runbook's Step 4:

```bash
for c in personal evojam parloa; do
  FISH=$(ssh marcin@10.0.1.91 "sudo -i -u marcin-$c command -v fish") || { echo "ERROR: fish not found for marcin-$c" >&2; continue; }
  ssh marcin@10.0.1.91 "grep -qxF '$FISH' /etc/shells || echo '$FISH' | sudo tee -a /etc/shells >/dev/null; sudo chsh -s '$FISH' marcin-$c"
  echo "marcin-$c -> $FISH"
done
```

Expected: a real fish path (e.g. ending in `.nix-profile/bin/fish`) for each user, no `ERROR` lines.

- [ ] **Step 7: Confirm the services are up and the shells are configured**

```bash
for c in personal evojam parloa; do
  echo "=== marcin-$c ==="
  ssh "marcin-$c@10.0.1.91" 'systemctl --user is-active claude-monitor-host claude-monitor-tail; \
    git config --get user.email; git config --get user.signingkey; \
    git config --get gpg.ssh.allowedSignersFile; test -r "$(git config --get gpg.ssh.allowedSignersFile)" && echo signers-readable'
  ssh marcin@10.0.1.91 "getent passwd marcin-$c | cut -d: -f7"
done
```

Expected per user: both services `active`; the identity's email; a signing key under `~/.ssh`; an allowed-signers path under `~/.config/git` that is readable; the passwd shell field ending in `/fish`. A `/run/secrets/...` value here means Task 5's overrides regressed; a non-fish shell means Step 6 did not take.

- [ ] **Step 8: Deploy the collector change**

Ship `nixos/envs/monitor.nix` to the monitor box and rebuild. Check for live ACP sessions first — the collector restart severs them.

```bash
curl -s http://10.0.1.123:8787/api/sessions | grep -c '"live":true' || true
cd /Users/marcinwadon/Projects/marcinwadon/nix-config
ssh root@10.0.1.123 'cat > /root/nix-config/nixos/envs/monitor.nix' < nixos/envs/monitor.nix
ssh root@10.0.1.123 'cd /root/nix-config && nixos-rebuild switch --flake .#monitor > /tmp/rebuild.log 2>&1; echo "exit=$?"; tail -5 /tmp/rebuild.log'
```

Expected: `exit=0`. Do not pipe the rebuild through `tail` directly — the pipeline's exit status would be `tail`'s, masking a failure.

- [ ] **Step 9: Verify the whole system from the collector's API**

```bash
echo "--- machines ---"
curl -s http://10.0.1.123:8787/api/machines
for c in personal evojam parloa; do
  printf "projects on m1-%s: " "$c"
  curl -s "http://10.0.1.123:8787/api/machines/m1-$c/projects" | head -c 200; echo
done
```

Expected: all three `m1-*` machines listed as connected, and each `projects` call returns HTTP 200. This is deliberately NOT "returns a non-empty list": `~/Projects` does not exist yet on a fresh user, and the enumerator skips a missing root rather than erroring, so `[]` here is normal until a repo is cloned into `~/Projects` on that user — it does not mean `WORKSPACE_ROOTS` is wrong. A machine missing from the first `curl` (not the emptiness of its `projects` list) is the actual signal that `WORKSPACE_ROOTS` or the collector restart did not take effect.

- [ ] **Step 10: Prove a real session works and lands in the right hat**

Start a session on `m1-parloa` from the dashboard, send a prompt, and confirm a reply. Then:

```bash
curl -s http://10.0.1.123:8787/api/sessions | grep -o '"machine":"m1-parloa"[^}]*"cwd":"[^"]*"' | head -3
```

Confirm in the browser that the session appears under the **Parloa** hat and not Personal. This is the only check that exercises `hatOf`'s new machine axis against real data; the unit tests cover the logic but not the wiring.

- [ ] **Step 11: Report what remains for the operator**

Report explicitly: the nix-config commits are **local and unpushed** (that repo is the operator's to push); the claude-monitor commits need pushing and a collector rebuild if the `hatOf` change is to reach the browser; the operator's Ghosthub work and `flake.lock` are untouched in the nix-config tree; `claude /login` (runbook Step 5) is still theirs to run for any user where a prompt returns `-32000 "Authentication required"`; and `gh auth login` (also runbook Step 5) is still theirs to run per user.

---

## Self-Review

**Spec coverage:**

| Spec requirement | Task |
|---|---|
| aarch64-linux FOD hash | 2 |
| `hatOf` machine-segment + stated precedence | 1 |
| `frontend.pnpmDeps` deliberately untouched | 2 (Step 6 proves the hook builds without forcing it) |
| `mkHome` takes `homeModules` | 3 |
| `monitorTokenFile` profile option | 4 |
| Three `m1-*` profiles, `shareClaudeConfig`, per-identity email | 5 |
| **Three sops paths overridden** | 5, Steps 6–7 (asserted, not assumed) |
| `allowed_signers` as plaintext repo file | 5, Step 1 |
| `WORKSPACE_ROOTS` | 6 |
| Runbook with root/automatable split | 7 |
| Users, lingering | 7 Step 1, executed in 8 |
| fish shell (`/etc/shells` + `chsh`, sequenced after activation) | 7 Step 4, executed in 8 |
| `claude /login` | 7 Step 5, executed in 8 |
| `nix-ld` not needed | 7 (recorded as a fact) |
| Reused signing keys per identity | 8 Step 4 |
| Three users ⇒ three `~/.claude` configs | 5 Step 7 proves per-user `MONITOR_MACHINE` |

No spec requirement is unclaimed. The seven-`claude`-logins risk is deliberately not a task: it is unverifiable in advance and fails loudly.

**Placeholder scan:** none. The one value that cannot be known in advance — the aarch64-linux FOD hash — is harvested by an exact command in Task 2 Step 3 and substituted in Step 4, which is a procedure, not a placeholder. `$TOKEN` / `$KEY` in the runbook are shell variables the adjacent comment explains how to fill; Task 8 Step 4 fills them programmatically.

**Type consistency:** `hasSegment(value, seg, sep = '/')` is used with three arguments in `hatOf`'s machine axis and two in its cwd axis, matching the signature in Task 1's Interfaces. `mkHome`'s `homeModules` parameter (Task 3) is passed by all three Task 5 call sites. `monitorTokenFile` (Task 4) is set in Task 5's `m1-common.nix`. `m1-common.nix` takes `{client, email}` and all three profiles call it with exactly those. Machine labels `m1-<client>` and usernames `marcin-<client>` are derived from the same `client` string, so Tasks 5, 6, 7 and 8 cannot drift apart.

**One mechanism worth naming, since it is used in a new way:** Task 5 delivers `allowed_signers` through `git.extraGitconfigFiles`, which until now has only carried gitconfig fragments (the Mac's `parloa.gitconfig`). That is safe rather than lucky: `home/programs/git/default.nix` implements it as a plain `home.file.".config/git/${name}".text` write with nothing gitconfig-specific about it, so arbitrary text is fine. Task 8 Step 7 additionally proves the written file is readable at the path git was told to use, which is the property that actually matters.
