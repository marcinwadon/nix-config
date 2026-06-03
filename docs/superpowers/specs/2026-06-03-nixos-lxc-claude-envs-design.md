# NixOS LXC Claude-coding environments — design

**Date:** 2026-06-03
**Status:** Approved (design); implementation plan pending

## Goal

Run three isolated environments on Proxmox LXC for Claude-assisted coding —
`personal`, `evojam`, `parloa` — each a reproducible NixOS container that reuses
this repo's existing home-manager dev setup (neovim, fish, tmux, zellij,
claude-code, git tooling), adapted for headless Linux.

A `personal` Debian 13 CT was created first, but we are pivoting to NixOS LXC for
all three (one Debian CT discarded). The macOS configuration
(`./switch home` / `./switch darwin`) is unaffected.

## Decisions (locked during brainstorming)

| Topic | Decision |
|-------|----------|
| Container base | **NixOS LXC**, `x86_64-linux` (Proxmox is x86_64) |
| Structure | **Shared base + per-env profiles**; home-manager reused as a NixOS module |
| Outputs model | One bootstrap LXC template → instantiate 3 CTs → `nixos-rebuild switch --flake .#<env>` (Approach A) |
| Secrets | **sops-nix**, host-key decryption via `ssh-to-age` (no separate private key to distribute) |
| Commit signing | **SSH signing** (`gpg.format = ssh`); one ed25519 key per env used for both GitHub auth and signing |
| Config scope | **Full, minus Mac-only** (drop `pinentry_mac`, Yubikey scdaemon, mac gpg-agent path) |
| Identity model | Per-env git identity, **shared Linux username `marcin`**, no gitdir includes in containers |
| Template build | **On the Proxmox host** (x86_64, native; avoids cross-arch emulation from the aarch64 Mac) |
| CT security | **Unprivileged** CT, passwordless sudo for `marcin` |
| Toolchains | **Minimal global base + per-project `direnv` + `flake.nix`** (no global SDKs baked in) |

### Approaches considered

- **A (chosen)** — Profiles + home-manager-as-NixOS-module + one bootstrap
  template, specialized per env via `nixos-rebuild`. Maximizes reuse, one source
  of truth in git, mirrors the existing `./switch` loop.
- **B (rejected)** — Bake a full per-env template each. Worse iteration loop:
  every change regenerates/re-uploads templates; drift risk; 3× artifacts.
- **C (rejected)** — Standalone home-manager on NixOS too. Loses NixOS ownership
  of users/ssh/sops wiring; two switch commands instead of one.

## Architecture

### Repo structure

```
flake.nix                    # multi-system: keep darwin outputs, ADD x86_64-linux + nixosConfigurations
outputs/
  home-conf.nix              # refactored: parameterized by { system, homeDirectory, profile }
  darwin-conf.nix            # unchanged
  nixos-conf.nix             # NEW: nixosConfigurations.{personal,evojam,parloa}
nixos/
  lxc-base.nix               # common: proxmox-lxc, user marcin, openssh, nix flakes, sops-nix, cachix, locale
  template.nix               # minimal config fed to nixos-generators (-f proxmox-lxc)
  envs/{personal,evojam,parloa}.nix   # = lxc-base + active profile + env sops file
home/
  home.nix                   # platform-aware (no hardcoded darwin / /Users)
  profiles/
    common.nix               # shared packages + programs (neovim, fish, tmux, zellij, git aliases)
    {personal,evojam,parloa}.nix   # identity, signing, toolchain, project bits, sops secret selection
  programs/...               # refactored: Mac-only blocks gated on pkgs.stdenv.isDarwin
secrets/
  .sops.yaml                 # age recipients (per-container host keys via ssh-to-age)
  {personal,evojam,parloa}.yaml   # sops-encrypted: github_token, ssh_signing_key(+.pub), env extras
```

The Darwin path keeps identical behavior — the darwin profile re-asserts today's
identity/packages. All new structure is additive.

### Platform-aware refactor (home modules)

- `home.nix`: `homeDirectory` derived (`/Users/${u}` darwin, `/home/${u}` linux);
  `username` from profile; drop the `darwin = true` specialArg in favor of
  `pkgs.stdenv.isDarwin`.
- Package list split: `commonPkgs ++ lib.optionals stdenv.isDarwin darwinPkgs ++ lib.optionals stdenv.isLinux linuxPkgs`.
  `pinentry_mac` → darwin only; `pinentry-curses` (or similar) → linux.
- `home.file.".gnupg/gpg-agent.conf"` and the whole `gpg`/Yubikey `scdaemonSettings`
  block: gated on `isDarwin`. On linux, GPG/Yubikey machinery is dropped entirely
  (signing is SSH-based, secrets via sops).
- `programs/default.nix`: `ssh.matchBlocks` becomes profile-supplied (linux gets
  its own / empty); gpg block gated; everything else cross-platform.
- `programs/git/default.nix`: identity (`user.*`, `commit.gpgsign`, `gpg.format`,
  `signingkey`) and the `parloa.gitconfig` include move OUT into per-env profiles.
  Shared module keeps aliases, pager, ignores, mergetool only.
- `outputs/home-conf.nix`: neovim-flake module/overlay references switch from
  hardcoded `aarch64-darwin` to the passed-in `system`.

**Risk:** neovim-flake, claude-code overlay, neovim-nightly, nix-search must
evaluate/build on `x86_64-linux`. Verify each during implementation; if one is
broken on linux, gate it behind `isDarwin` so the container still builds (lean
fallback for that package only).

### NixOS LXC base + provisioning

`nixos/lxc-base.nix`:
- `proxmox-lxc` module; unprivileged; `proxmoxLXC.manageNetwork = false`
  (Proxmox owns the CT network).
- `users.users.marcin`: normal user, fish shell, `wheel` group; passwordless sudo
  (`security.sudo.wheelNeedsPassword = false`).
- `services.openssh`: key-only auth.
- `nix.settings.experimental-features = [ "nix-command" "flakes" ]`; reuse
  `system/cachix*` substituters.
- `home-manager.users.marcin = import ../home/home.nix` with the env profile via
  `extraSpecialArgs`.
- locale/timezone, `system.stateVersion`.

`nixos/envs/<env>.nix`: `imports = [ ../lxc-base.nix ]` + active profile + env
sops file. Thin.

`nixos/template.nix`: minimal bootable config (flakes on, openssh, user, git) —
**not** env-specific.

**Provisioning flow (per container, one-time):**
1. On the Proxmox host: `nix run github:nix-community/nixos-generators -- -f proxmox-lxc -c ./nixos/template.nix -o ./result`.
2. Upload tarball to CT-template storage; `pct create` from it (×3).
3. First boot: SSH in / `pct enter`; clone this repo.
4. Grab host key → age recipient:
   `ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub` → add to `.sops.yaml` for that
   env; re-encrypt `secrets/<env>.yaml`; commit.
5. `sudo nixos-rebuild switch --flake .#<env>`.
6. Add the env's `ssh_signing_key.pub` to that GitHub account as **both**
   Authentication and Signing key.

Thereafter iterate with `nixos-rebuild switch --flake .#<env>` (= `./switch nixos <env>`).

### Secrets (sops-nix) + signing

- **Decryption:** host-key via `ssh-to-age`. No separate age private key to store;
  recipients are per-container, so each env's secrets are isolated.
  - *Fallback* (if first-boot chicken-and-egg is unwanted): per-env age keypair
    generated locally, public recipient committed, private key dropped at
    `/var/lib/sops-nix/key.txt` at provisioning.
- **`secrets/<env>.yaml` contents:**
  - `github_token` — replaces `sessionVariables.GITHUB_TOKEN = import ./secrets/github`
    (which currently leaks into the world-readable Nix store). Decrypted to
    `/run/secrets/github_token` (mode `0400`, owner `marcin`); sourced by the shell
    at runtime, not embedded in the store.
  - `ssh_signing_key` (+ `.pub`) — per-env ed25519, used for GitHub auth AND
    signing.
  - env extras (e.g. Parloa's `parloa.gitconfig` content) — retires git-crypt on
    the linux side.
- **Signing wiring (per-env profile):**
  ```nix
  programs.git.settings = {
    user.signingkey = "/run/secrets/ssh_signing_key.pub";
    gpg.format = "ssh";
    commit.gpgsign = true;
    gpg.ssh.allowedSignersFile = <allowed_signers>;  # local verification
  };
  ```
- **git-crypt:** unchanged for the Darwin path; containers don't use it. No
  migration of existing Mac secrets required.

### Per-env profiles, toolchains & workflow

- `home/profiles/common.nix`: shared packages + programs.
- `home/profiles/<env>.nix`: one git identity + SSH signing, env sops file,
  env toolchain selection, env project bits:
  - `personal` / `evojam`: Constellation scripts (`h_mainnet`/`h_testnet`/
    `h_integrationnet`) + `clean-bsp-workspace`.
  - `parloa`: `parloa.gitconfig`.
- **Toolchains:** minimal global base only; language SDKs come per-project via
  `direnv` + each repo's `flake.nix`. Keeps containers lean and reproducible.
- **`switch` script** (extended):
  - `./switch home` / `./switch darwin` — unchanged (Mac).
  - `./switch template` — generate the proxmox-lxc tarball (run on Proxmox host).
  - `./switch nixos <env>` — `sudo nixos-rebuild switch --flake .#<env>` (inside CT).
  - platform-detect so one checked-out repo behaves correctly on Mac vs container.
- **Docs:** this spec + an operational runbook (build → upload → `pct create` →
  first-boot bootstrap → `./switch nixos <env>`).

## Cross-arch note

The Mac is aarch64-darwin; the template is x86_64-linux. Build the template on the
Proxmox host (native x86_64). Emulation (binfmt/linux-builder) is a documented but
slower fallback.

## Out of scope

- Converting the Mac to anything; Darwin behavior is frozen.
- Proxmox host configuration beyond installing Nix + uploading templates.
- Per-project `flake.nix` files (created per repo as needed, not here).

---

*Generated with Claude AI — please review before distribution.*
