# Mac mini M1 (Asahi) as a claude-monitor fleet host — design

## Goal

Add a Mac mini M1 running Fedora Asahi Remix 44 Server (`mini`, `10.0.1.91`) to
the fleet as a **fully configured working host**: fish, direnv, flakes, the shared
Claude Code config, git identity and signing — the same working environment the
Proxmox CTs have, plus the claude-monitor ACP host and transcript tailer so the
dashboard can start and drive sessions on it.

Motivation is measured, not aesthetic: the R320's 2012 Xeon is ~5.8x slower than
the Mac and 56% of session wall-clock is tool execution, so the CTs are the
fleet's throughput floor. The M1 is 8 cores / 15 GiB / 382 GB free.

The CTs stay. This adds a host; it does not migrate one.

## Decisions (locked during brainstorming)

| Fork | Decision |
|---|---|
| Role | Full working host, declarative parity with the CTs — not a bare ACP endpoint |
| System layer | **Keep Asahi**, add Nix + standalone home-manager (the Mac's pattern) |
| Identity model | **Three unix users**, CT-style isolation: `marcin-personal`, `marcin-evojam`, `marcin-parloa` |
| Machine labels | `m1-personal` / `m1-evojam` / `m1-parloa`, plus a `hatOf` extension |
| Secrets | Plain files on the box (the Mac's pattern), **no sops** |
| Signing keys | **Reuse the CTs' existing keys** — one key per client *identity*, not per machine |
| Kernel | **16K stays** — proven unnecessary to switch (see below) |

### Approaches considered

**Full NixOS via `nixos-apple-silicon`** — rejected: reinstalls a working box, and
`outputs/nixos-conf.nix` hardcodes `system = "x86_64-linux"` while every env
imports `nixos/lxc-base.nix` (the proxmox-lxc module), so it would need a
base/LXC split before the first build. Zero imperative margin, disproportionate
cost.

**No Nix at all** (cross-compiled binary + hand-written unit + install script) —
seriously considered, because it would double as the discovery path for shipping
claude-monitor to non-Nix machines, and because the M1 is the only clean-room
non-Nix Linux box available (installing Nix burns that clean room irreversibly).
Rejected because the requirement is a *fully configured* host, and the script
delivers only the monitor host — not fish, direnv, flakes, toolchain or the shared
Claude config. The distribution-path question is real and stays open as separate
work.

**Single user, Mac-style** (one box, all three clients, git identity per directory
via `git.includes`) — rejected in favour of real `$HOME` isolation and separate
signing keys per identity.

**Switching to the 4K kernel** — considered as the escape hatch from page-size
incompatibility. `kernel.aarch64` ships at the *same version* as the installed
`kernel-16k` from the same `@asahi` copr repo, so it is a flip, not a downgrade.
Not needed: see the verification below. It costs TLB performance on hardware
designed around 16K and rules out GPU acceleration, so it stays a fallback only.

## Verified on the machine (measured, not assumed)

The 16K page size (`getconf PAGESIZE` = 16384, kernel
`7.1.6-400.asahi.fc44.aarch64+16k`) is a documented hazard: `cache.nixos.org`
builds aarch64-linux for 4K pages, and software that bakes page size in at
**build** time rather than querying at runtime fails. The named upstream cases are
jemalloc, Zig, Wine and box86. The failure class is narrow, so it was tested
rather than reasoned about:

| Probe | Result | Why this one |
|---|---|---|
| `glibc-2.42` from the cache | OK | Make-or-break: dynamic loader + libc |
| `nodejs_22` alloc (2M array + 1 MiB Buffer) | v22.23.2 OK | V8 memory |
| `nodejs_22` JIT (5·10⁷ loop) | OK | V8 codegen — load-bearing for the adapter |
| `ripgrep` 15.2.0 | OK | Deliberately chosen: the jemalloc risk class |
| `neovim` headless Lua | OK | LuaJIT |
| `fish`, `git`, `gh`, `fd`, `bat`, `jq`, `eza` | all OK | The real `home.packages` set |
| `claude-agent-acp@0.63.0` install | OK, resolved `claude-agent-sdk-linux-arm64` | A **prebuilt** arm64 binary — the named risk class |
| adapter `initialize` handshake | OK — `protocolVersion:1`, `loadSession:true`, session caps resume/close/fork/list | Proves the adapter runs, not just installs |

**Nix must be installed with `sudo dnf install nix`** (Fedora 44 packages it),
not the nixos.org shell installer, which *deliberately aborts* under SELinux
enforcing. Done: nix 2.34.8, `nix-daemon` active, no SELinux denials.

## Architecture

### Layer ownership

1. **Asahi — imperative, outside git.** Kernel, firmware, disk and the one-time
   bootstrap. Captured as a runbook, not as code.
2. **nix-config — declarative.** Three standalone `homeConfigurations`, each
   rebuilt from its own user's account.
3. **claude-monitor — declarative.** The aarch64-linux FOD hash and the `hatOf`
   extension.
4. **Collector — configuration.** `WORKSPACE_ROOTS` in `nixos/envs/monitor.nix`.

### claude-monitor changes (one small PR, two commits)

**aarch64-linux support.** `flake.nix` computes
`claude-agent-acp-modules.outputHash` as `{x86_64-linux; aarch64-darwin}.${system}`,
so on aarch64-linux this is an **eval throw**, not a build failure — every
Nix-based route is blocked until the hash exists. Add the third entry, computed on
the M1 (a darwin build cannot produce it: the installed tree carries a
platform-specific `@anthropic-ai/claude-agent-sdk-*`).

The `frontend.pnpmDeps.hash` attrset has the same shape and is deliberately left
alone: overlays are lazy and `claude-monitor-hook` sets `subPackages`, so the
frontend derivation is never forced on this platform. If someone later evaluates
`pkgs.claude-monitor` (the collector) on aarch64-linux it will throw — acceptable,
since the collector runs only on the x86_64 monitor box.

**`hatOf` matches a machine-name segment.** `frontend/src/lib/hats.ts` matches the
machine name *exactly* (`s.machine === 'parloa'`), so `m1-parloa` would fall
through to the `personal` bucket. The cwd-segment clause does not save it: on the
CTs repos live at `/home/marcin/Projects/<repo>` with no client segment (which is
why only 45 of 162 Parloa-scoped sessions matched by machine name). Add a
machine-name segment match (split on `-`) alongside the existing cwd-segment
match, so hat membership is **guaranteed by the label** rather than by where a
repo happens to be cloned. One file, plus a test. Generalises to any future box.

This adds a *third* signal, so precedence must be stated rather than left to the
reader: **machine-exact → machine-segment → cwd-segment**, with the client checks
still ordered parloa before evojam as today. The consequence to be explicit about:
a session on `m1-personal` with a cwd under `~/Projects/parloa` buckets as
**parloa**, because the parloa clauses are evaluated first — consistent with the
existing comment that the repo is the stronger signal. The buckets stay a total
partition (`personal` remains the complement), so no session can vanish from every
hat.

### nix-config changes (second PR)

- **`outputs/home-conf.nix`: `mkHome` takes `homeModules`.** It currently imports
  `neovim-flake.homeManagerModules.${system}` unconditionally; on aarch64-linux
  that would try to source-build neovim, which the repo's own comment rules out
  ("crates.io blocks the pinned old nixpkgs's cargo-vendor User-Agent"). The NixOS
  path already passes `homeModules = []`, so this unifies an existing pattern
  rather than inventing one.
- **New profile option `monitorTokenFile`** in `home/lib/profile-defaults.nix`.
  `home/programs/claude-monitor-hook/default.nix` hardcodes
  `/run/secrets/monitor_token` for all of Linux. The default preserves today's
  behaviour exactly, so CTs and the Mac are untouched. Note the failure mode this
  guards: the wrapper does `[ -r "$f" ] && export MONITOR_TOKEN=…`, so an
  unreadable token file means the variable is silently unset and the host simply
  never registers.
- **Three profiles `home/profiles/m1-{personal,evojam,parloa}.nix`**, sharing a
  small `m1-common.nix` base: `shareClaudeConfig = true` (as on the CTs),
  `monitorMachine = "m1-<client>"`, per-identity `git.userEmail`, per-user
  `username`.
- **`m1-common.nix` MUST override three inherited sops paths, and this is the one
  place a mistake fails silently.** `home/profiles/common.nix` — the shared Linux
  base — hardcodes **three** absolute `/run/secrets/*` paths that do not exist on
  this box: `sshMatchBlocks."github.com".identityFile`, `git.signing.key` and
  `git.signing.allowedSignersFile`. Inheriting them without override leaves a box
  that **cannot push** (missing `identityFile`, surfacing only at the first `git
  push`) and **cannot sign**. All three are already profile values, so no new
  options are needed — but all three must be repointed at `~/.ssh/…` and the
  repo's plaintext `allowed_signers`. Whether `m1-common.nix` imports `common.nix`
  and overrides, or stands alone, is a plan-level call; either way the three
  overrides are mandatory and belong in the plan's verification step.
- **`allowed_signers` as a plaintext file in the repo.** It contains only *public*
  keys; there is no reason for it to be a secret. The M1 profiles point at it. The
  CTs stay on sops in this change — converting them is obvious follow-up, not
  scope.
- **`nixos/envs/monitor.nix`: `WORKSPACE_ROOTS`** gains
  `m1-personal=/home/marcin-personal/Projects`, and the same for the other two
  (`;` between machines, `,` between roots). Without this the project picker is
  **silently empty** — a machine absent from the value enumerates `[]` and the
  endpoint still returns 200. Requires a collector restart. The orchestrator's own
  copy of `WORKSPACE_ROOTS` is mac-only today; extending it so NL launches can
  target the M1 is deliberate follow-up.
- **`docs/RUNBOOK-m1-asahi.md`**, following `docs/RUNBOOK-lxc.md`.

### Secrets and signing

One shared monitor token, copied to `~/.config/claude-monitor/token` (mode 600)
for each of the three users — the exact path the hook module already uses on
darwin.

Signing keys are reused from the matching CT: `ssh marcin@10.0.1.12x
'cat /run/secrets/ssh_signing_key'` → `~/.ssh/id_ed25519_signing`, mode 600. The
key represents the *client identity*, not the machine, so reuse keeps the existing
"one key per identity" model instead of diluting it to one per identity × machine.
It also avoids adding three new entries to `allowed_signers` in every place it
lives — a miss there shows up later as commits reading *unverified* under
`git log --show-signature`, which is exactly the kind of slow, silent drift worth
paying to avoid.

Note that `sshMatchBlocks` in `home/profiles/common.nix` points GitHub's
`IdentityFile` at the same key, so it serves both signing and authentication:
reuse means the M1 also authenticates to GitHub as that identity.

Accepted cost: one key compromise now covers two machines. Marginal on a private
LAN with the operator's own hardware, but real.

### Bootstrap: what needs root

`sudo` requires a password on this box, so the runbook splits cleanly and the
root half **cannot** be automated:

**Operator (root):** create the three users and add the ssh key to each one's
`authorized_keys`; `loginctl enable-linger` for each (currently `Linger=no` —
without it the host runs only while an ssh session is open and disappears on
logout; the CTs get this from `users.users.marcin.linger` in `nixos/lxc-base.nix`,
which does not exist here); add fish to `/etc/shells` (only `sh` and `bash` are
listed) and `chsh` each user.

**Operator (interactive, per user):** `claude /login`. Three times — it cannot be
scripted.

**Automatable, as each user:** `~/.config/nix/nix.conf` (flakes), the token file,
the signing key, `home-manager switch --flake .#m1-<client>`.

`nix-ld` is **not** needed here. The CTs run the native `claude` from
`~/.local/bin` through nix-ld because they are NixOS; Fedora is an ordinary glibc
distribution and `pkgs.claude-code` — already in `home.packages` — works
directly. One fewer moving part than on the CTs.

## All three keys are reachable

Reuse briefly looked executable for only two identities out of three: the
`personal` CT had been unreachable for roughly four weeks, and
`secrets/personal.yaml` is encrypted to exactly one recipient (`personal_host`,
the age key derived from that CT's ssh host key) with the Mac holding no
recipient — so the key was unrecoverable while the CT was down. The operator
brought the CT back during this design, and all three keys are now present and
readable. **Reuse is uniform across all three identities: no new key, no GitHub
registration, no additions to `allowed_signers`.**

(A dead CT does not actually mean a lost key — the recovery route is recorded in
project memory rather than here, since this contingency closed.)

**Three users means three of everything under `~/.claude`, not one shared config.**
`home.activation.claudeMonitorHooks` jq-merges each user's own
`~/.claude/settings.json`, and each user's hook wrapper carries a *different*
`MONITOR_MACHINE`. `shareClaudeConfig = true` symlinks the read-only shared config
(CLAUDE.md, skills, commands, agents) from the store into each `$HOME` separately
and seeds writable memory-rule stubs per user. That is correct and intended, but a
reader will assume one shared config, so: three settings files, three hook
commands, three sets of grown memory rules. The nix store is shared, so there is no
disk duplication.

## Risks

- **Seven `claude` logins on one subscription** (Mac + 3 CTs + 3 M1 users), up
  from four. No documented hard limit is known, but it is a real change of scale.
- **Asahi kernel updates** could in principle change page-size behaviour, and a
  *new* dependency could bake page size at build time. The mitigation is to
  re-probe rather than re-assume; the probe set is recorded above.
- **The adapter version must stay pinned to the flake's.** The pin decides which
  model the dashboard's aliases resolve to (`opus[1m]` → Opus 5 on 0.63.0), so a
  box on a different adapter version would silently run a different model.
- **Three home-manager generations to keep in step.** A change to shared modules
  needs three `switch` runs on this box, not one.

## Out of scope

- Migrating or retiring any CT.
- Converting the CTs' `allowed_signers` from sops to plaintext.
- The orchestrator's `WORKSPACE_ROOTS` (NL launches targeting the M1).
- A non-Nix install script / distribution path for the claude-monitor host — a
  genuinely valuable, separate piece of work.
- GPU acceleration, desktop, or anything requiring the 4K kernel.
