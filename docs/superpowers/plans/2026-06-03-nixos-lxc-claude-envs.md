# NixOS LXC Claude-coding environments — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add three reproducible NixOS LXC environments (`personal`, `evojam`, `parloa`) for Claude-assisted coding on Proxmox, reusing this repo's home-manager dev setup as a NixOS module, without changing macOS behavior.

**Architecture:** Refactor the `home/` modules to be platform-aware (Mac-only bits gated on `pkgs.stdenv.isDarwin`), drive per-environment differences from a `profile` specialArg, and add `nixosConfigurations.{personal,evojam,parloa}` that compose a shared `lxc-base` + a thin per-env module + home-manager-as-NixOS-module + sops-nix. A single bootstrap LXC template (built via nixos-generators on the Proxmox host) is instantiated 3× and specialized with `nixos-rebuild switch --flake .#<env>`.

**Tech Stack:** Nix flakes, home-manager, nix-darwin (existing), NixOS, sops-nix, nixos-generators (proxmox-lxc), ssh-to-age, SSH commit signing.

**Spec:** `docs/superpowers/specs/2026-06-03-nixos-lxc-claude-envs-design.md`

---

## Verification model (read first)

This repo has no unit-test framework; the "tests" are Nix evaluation/build assertions.

- **Darwin regression anchor (run on the Mac after every refactor task):**
  ```bash
  nix build .#homeConfigurations.marcinwadon.activationPackage --no-link --print-out-paths
  ```
  Expected output path (pure refactors must NOT change it):
  `/nix/store/wr4s6mgg2f95g6ylmqlgs5q9379bnycq-home-manager-generation`
  If the hash changes, the refactor altered the Darwin config — investigate before continuing. (The hash legitimately changes only in Task 9, when we adopt the new `programs.git.signing` option, and at flake-input lock changes; note the new hash there.)
- **Linux config eval (runs on the aarch64 Mac — evaluation only, no build):**
  ```bash
  nix eval .#nixosConfigurations.<env>.config.system.build.toplevel.drvPath
  ```
  Returns a `.drv` path on success; errors if the config doesn't evaluate. Building the toplevel requires x86_64-linux and is deferred to the Proxmox host (Tasks 10–11).
- **Format:** `nix fmt` (alejandra) before each commit.

Use Conventional Commits. Commit directly to `main` (personal repo, trunk-based — matches repo history).

---

## File Structure

**Created:**
- `outputs/nixos-conf.nix` — builds `nixosConfigurations.{personal,evojam,parloa}`.
- `nixos/lxc-base.nix` — shared NixOS layer (proxmox-lxc, user `marcin`, openssh, nix, cachix, home-manager + sops wiring).
- `nixos/template.nix` — minimal bootable config for the generated template.
- `nixos/envs/personal.nix`, `evojam.nix`, `parloa.nix` — thin per-env modules.
- `home/profiles/common.nix` — shared package/program selection (data, not a module).
- `home/profiles/darwin.nix` — reproduces today's macOS identity/packages/secrets.
- `home/profiles/personal.nix`, `evojam.nix`, `parloa.nix` — per-env Linux profiles.
- `home/lib/profile-defaults.nix` — profile schema defaults (so every module can read `profile.*` safely).
- `secrets/.sops.yaml` — sops recipients/rules.
- `secrets/personal.yaml`, `evojam.yaml`, `parloa.yaml` — sops-encrypted (created during provisioning; placeholders documented).
- `docs/RUNBOOK-lxc.md` — operational runbook.

**Modified:**
- `flake.nix` — add inputs (`sops-nix`, `nixos-generators`), add `x86_64-linux` outputs (`nixosConfigurations`, `packages.x86_64-linux.lxcTemplate`).
- `outputs/home-conf.nix` — parameterize by `{ system, homeDirectory, profile }`; `system`-driven neovim-flake refs.
- `home/home.nix` — derive `homeDirectory`, drop the `darwin` arg, package buckets, gate gpg-agent file, read `profile`.
- `home/programs/default.nix` — gate `gpg`/`ssh` blocks; read `profile`.
- `home/programs/git/default.nix` — move identity/signing/includes into `profile.git`.
- `home/programs/fish/default.nix` — Linux-only: source `github_token` from `/run/secrets`.
- `switch` — add `template` and `nixos <env>` subcommands; platform-detect.

---

## Task 0: Add flake inputs and verify Darwin still builds

**Files:**
- Modify: `flake.nix:5-50` (inputs block)

- [ ] **Step 1: Add the two new inputs**

In `flake.nix`, inside `inputs = { ... }`, after the `claude-code` input, add:

```nix
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
```

- [ ] **Step 2: Lock the new inputs**

Run: `nix flake lock`
Expected: `flake.lock` updated with `sops-nix` and `nixos-generators` nodes; no errors.

- [ ] **Step 3: Darwin regression check**

Run: `nix build .#homeConfigurations.marcinwadon.activationPackage --no-link --print-out-paths`
Expected: `/nix/store/wr4s6mgg2f95g6ylmqlgs5q9379bnycq-home-manager-generation` (unchanged — adding unused inputs doesn't affect the output).

- [ ] **Step 4: Commit**

```bash
nix fmt
git add flake.nix flake.lock
git commit -m "build(flake): add sops-nix and nixos-generators inputs"
```

---

## Task 1: Profile schema defaults

Create the profile schema so every home module can read `profile.*` with safe defaults. This is data consumed via the `profile` specialArg.

**Files:**
- Create: `home/lib/profile-defaults.nix`

- [ ] **Step 1: Write the defaults file**

```nix
# Default values for the per-environment `profile` specialArg.
# Each profile (home/profiles/<env>.nix) overrides a subset of these.
{
  username = "marcin";

  # Git identity + signing for this environment.
  git = {
    userName = "Marcin Wadon";
    userEmail = "marcin@example.invalid"; # always overridden by a profile
    signing = {
      enable = false;
      format = "ssh"; # "ssh" | "openpgp"
      key = null; # signing key (ssh pubkey path, or gpg key id)
      signByDefault = false;
      allowedSignersFile = null; # ssh signing: path to allowed_signers
    };
    includes = []; # list of { condition; path; } for gitdir includes
    extraGitconfigFiles = {}; # name -> text, written under ~/.config/git/
  };

  # Extra packages for this env, as a function of pkgs (kept minimal — see spec).
  extraPackages = _pkgs: [];

  # Toggles for project-specific bits.
  enableConstellationScripts = false; # h_mainnet/h_testnet/h_integrationnet
  enableBspCleanup = false; # clean-bsp-workspace

  # SSH client config (home-manager programs.ssh.matchBlocks).
  sshMatchBlocks = {};

  # Runtime path to a GitHub token file (sops-provisioned on Linux); null on Darwin.
  githubTokenFile = null;

  # Build-time GitHub token (Darwin only, from git-crypt secret); null elsewhere.
  githubToken = null;
}
```

- [ ] **Step 2: Verify it evaluates**

Run: `nix eval --impure --expr '(import ./home/lib/profile-defaults.nix).username'`
Expected: `"marcin"`

- [ ] **Step 3: Commit**

```bash
nix fmt
git add home/lib/profile-defaults.nix
git commit -m "feat(home): add per-environment profile schema defaults"
```

---

## Task 2: Refactor `home/home.nix` to be platform-aware and profile-driven

**Files:**
- Modify: `home/home.nix` (whole file)

- [ ] **Step 1: Replace the file with the platform-aware version**

```nix
{
  config,
  lib,
  pkgs,
  profile ? {},
  ...
}: let
  defaults = import ./lib/profile-defaults.nix;
  p = lib.recursiveUpdate defaults profile;

  username = p.username;
  homeDirectory =
    if pkgs.stdenv.isDarwin
    then "/Users/${username}"
    else "/home/${username}";

  commonPkgs = [
    pkgs.alejandra
    pkgs.any-nix-shell
    pkgs.oxfmt
    pkgs.oxlint
    pkgs.asciinema
    pkgs.bottom
    pkgs.cachix
    pkgs.claude-code
    pkgs.dig
    pkgs.duf
    pkgs.eza
    pkgs.fd
    pkgs.gh
    pkgs.killall
    pkgs.lnav
    pkgs.mosh
    pkgs.ncdu
    pkgs.nyancat
    pkgs.nix-index
    pkgs.nix-output-monitor
    pkgs.prettyping
    pkgs.ripgrep
    pkgs.tldr
    pkgs.tree
  ];

  darwinPkgs = [pkgs.pinentry_mac];
  linuxPkgs = [pkgs.pinentry-curses];

  defaultPkgs =
    commonPkgs
    ++ lib.optionals pkgs.stdenv.isDarwin darwinPkgs
    ++ lib.optionals pkgs.stdenv.isLinux linuxPkgs
    ++ (p.extraPackages pkgs);
in {
  programs.home-manager.enable = true;

  imports = builtins.concatMap import [
    ./programs
    ./scripts
  ];

  home = {
    inherit username homeDirectory;
    stateVersion = "24.11";

    packages = defaultPkgs;

    sessionVariables =
      {EDITOR = "nvim";}
      // lib.optionalAttrs (p.githubToken != null) {
        GITHUB_TOKEN = p.githubToken;
      };

    # Darwin-only: pinentry-mac path + GPG agent SSH support.
    file = lib.optionalAttrs pkgs.stdenv.isDarwin {
      ".gnupg/gpg-agent.conf".text = ''
        pinentry-program ${pkgs.pinentry_mac}/Applications/pinentry-mac.app/Contents/MacOS/pinentry-mac
        enable-ssh-support
        default-cache-ttl 28800
        max-cache-ttl 28800
      '';
    };
  };
}
```

Notes for the implementer:
- `profile ? {}` makes the arg optional and removes the old `darwin` specialArg.
- `p` is the merged profile (defaults + the env's overrides).
- On Darwin, the profile (Task 4) sets `githubToken = import ./secrets/github`, reproducing today's behavior; on Linux it's `null` and the token comes from a runtime file (Task 7).
- The scripts import (`./scripts`) still loads all scripts; gating which scripts are active happens inside the scripts module in Task 6 of the home layer — for now scripts remain as-is (they're harmless to include).

- [ ] **Step 2: Update `outputs/home-conf.nix` to pass `profile` instead of `darwin`** (temporary inline profile; replaced in Task 5)

In `outputs/home-conf.nix`, change the `mkHome` block's `extraSpecialArgs`:

```nix
    extraSpecialArgs = {profile = import ../home/profiles/darwin.nix;};
```

(The file `home/profiles/darwin.nix` is created in Task 4. To keep this task's verification green before Task 4 exists, temporarily use `extraSpecialArgs = {profile = {username = "marcinwadon"; githubToken = import ../home/secrets/github;};};` — but you will replace it in Task 5. If you implement tasks in order with a subagent, prefer doing Task 4 before re-running the Darwin check.)

- [ ] **Step 3: Verify (after Task 4 exists) — Darwin regression check**

Run: `nix build .#homeConfigurations.marcinwadon.activationPackage --no-link --print-out-paths`
Expected: same hash as baseline once the Darwin profile fully reproduces the old config: `/nix/store/wr4s6mgg2f95g6ylmqlgs5q9379bnycq-home-manager-generation`.
(If you run it now, before Tasks 3–4, expect a different hash or an eval error referencing the missing profile/git settings — that's fine; the anchor is asserted at the end of Task 4.)

- [ ] **Step 4: Commit**

```bash
nix fmt
git add home/home.nix outputs/home-conf.nix
git commit -m "refactor(home): make home.nix platform-aware and profile-driven"
```

---

## Task 3: Gate `gpg`/`ssh` in `programs/default.nix` and parameterize the git module

**Files:**
- Modify: `home/programs/default.nix`
- Modify: `home/programs/git/default.nix`

- [ ] **Step 1: Rewrite `home/programs/default.nix` to gate Mac-only blocks**

```nix
let
  more = {
    pkgs,
    lib,
    profile ? {},
    ...
  }: let
    defaults = import ../lib/profile-defaults.nix;
    p = lib.recursiveUpdate defaults profile;
  in {
    programs = {
      bat.enable = true;

      broot = {
        enable = true;
        enableFishIntegration = true;
      };

      direnv = {
        enable = true;
        nix-direnv.enable = true;
      };

      fzf = {
        enable = true;
        enableFishIntegration = true;
        defaultCommand = "fd --type file --follow";
        defaultOptions = ["--height 20%"];
        fileWidgetCommand = "fd --type file --follow";
      };

      # GPG + Yubikey scdaemon: Darwin only (containers sign over SSH, secrets via sops).
      gpg = lib.mkIf pkgs.stdenv.isDarwin {
        enable = true;
        publicKeys = [
          {
            source = ../../public.gpg;
            trust = "ultimate";
          }
        ];
        scdaemonSettings = {
          reader-port = "Yubico Yubi";
          disable-ccid = true;
        };
      };

      htop = {
        enable = true;
        settings = {
          sort_direction = true;
          sort_key = "PERCENT_CPU";
        };
      };

      jq.enable = true;

      ssh = {
        enable = true;
        matchBlocks =
          if pkgs.stdenv.isDarwin
          then import ../secrets/ssh.nix
          else p.sshMatchBlocks;
      };
    };
  };
in [
  ./git
  ./fish
  ./tmux
  ./zellij
  ./neovim-ide
  ./claude-code
  more
]
```

- [ ] **Step 2: Rewrite `home/programs/git/default.nix` to read identity/signing from `profile.git`**

```nix
{
  config,
  pkgs,
  lib,
  profile ? {},
  ...
}: let
  defaults = import ../../lib/profile-defaults.nix;
  p = lib.recursiveUpdate defaults profile;
  g = p.git;

  rg = "${pkgs.ripgrep}/bin/rg";

  baseConfig = {
    core = {
      editor = "nvim";
      pager = "diff-so-fancy | less --tabs=4 -RFX";
    };
    init.defaultBranch = "main";
    merge = {
      conflictStyle = "diff3";
      tool = "vim_mergetool";
    };
    mergetool."vim_mergetool" = {
      cmd = "nvim -f -c \"MergetoolStart\" \"$MERGED\" \"$BASE\" \"$LOCAL\" \"$REMOTE\"";
      prompt = false;
    };
    pull.rebase = false;
    push.autoSetupRemote = true;
    url = {
      "https://github.com/".insteadOf = "gh:";
      "ssh://git@github.com".pushInsteadOf = "gh:";
    };
  };

  identityConfig =
    {
      user = {
        email = g.userEmail;
        name = g.userName;
      };
    }
    // lib.optionalAttrs g.signing.enable {
      commit.gpgsign = g.signing.signByDefault;
      gpg.format = g.signing.format;
      user.signingkey = g.signing.key;
    }
    // lib.optionalAttrs (g.signing.enable && g.signing.format == "ssh" && g.signing.allowedSignersFile != null) {
      gpg.ssh.allowedSignersFile = g.signing.allowedSignersFile;
    };

  aliases = {
    amend = "commit --amend -m";
    fixup = "!f(){ git reset --soft HEAD~\${1} && git commit --amend -C HEAD; };f";
    loc = "!f(){ git ls-files | ${rg} \"\\.\${1}\" | xargs wc -l; };f";
    br = "branch";
    co = "checkout";
    st = "status";
    ls = "log --pretty=format:\"%C(yellow)%h%Cred%d\\\\ %Creset%s%Cblue\\\\ [%cn]\" --decorate";
    ll = "log --pretty=format:\"%C(yellow)%h%Cred%d\\\\ %Creset%s%Cblue\\\\ [%cn]\" --decorate --numstat";
    cm = "commit -m";
    ca = "commit -am";
    dc = "diff --cached";
    lg = "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit --date=relative";
    amm = "commit --amend";
    mr = "merge --ff-only";
  };
in {
  home.packages = with pkgs; [
    diff-so-fancy
    git-crypt
    hub
    tig
  ];

  # Extra gitconfig files written under ~/.config/git/ (e.g. Parloa's).
  home.file =
    lib.mapAttrs'
    (name: text: lib.nameValuePair ".config/git/${name}" {inherit text;})
    g.extraGitconfigFiles;

  programs.git = {
    enable = true;
    settings = baseConfig // identityConfig // {alias = aliases;};
    includes = g.includes;
    ignores = [
      "*.bloop"
      "*.bsp"
      "*.metals"
      "*.metals.sbt"
      "*metals.sbt"
      "*.direnv"
      "*.envrc"
      "*hie.yaml"
      "*.mill-version"
      "*.jvmopts"
      ".DS_Store"
    ];
  };
}
```

- [ ] **Step 3: (defer verification to Task 4)** — these modules now require `profile.git` to be populated. Verification happens once `home/profiles/darwin.nix` exists. Do not commit yet if running strictly in order; otherwise commit and let Task 4 assert the anchor.

- [ ] **Step 4: Commit**

```bash
nix fmt
git add home/programs/default.nix home/programs/git/default.nix
git commit -m "refactor(home): gate gpg/ssh on darwin, drive git identity from profile"
```

---

## Task 4: Darwin profile (freeze macOS behavior) + assert the regression anchor

**Files:**
- Create: `home/profiles/darwin.nix`
- Modify: `outputs/home-conf.nix` (use the darwin profile)

- [ ] **Step 1: Create `home/profiles/darwin.nix` reproducing today's config**

```nix
# Darwin profile — reproduces the pre-refactor macOS configuration exactly.
let
  parloaSecrets = import ../secrets/parloa.nix;
in {
  username = "marcinwadon";

  githubToken = import ../secrets/github;

  git = {
    userName = "Marcin Wadon";
    userEmail = "mwadon@evojam.com";
    signing = {
      enable = true;
      format = "openpgp";
      key = "23E5A318AE8D2861";
      signByDefault = true;
      allowedSignersFile = null;
    };
    includes = [
      {
        condition = "gitdir:${parloaSecrets.projectPath}";
        path = "~/.config/git/parloa.gitconfig";
      }
    ];
    extraGitconfigFiles = {
      "parloa.gitconfig" = parloaSecrets.gitConfig;
    };
  };
}
```

Implementer note: confirm `parloaSecrets` exposes `projectPath` and `gitConfig` (it did pre-refactor — `git-crypt` must be unlocked locally to read `home/secrets/parloa.nix`). The original config used `commit.gpgsign = true` and `gpg.format` unset (defaulting to openpgp). Setting `format = "openpgp"` explicitly is equivalent.

- [ ] **Step 2: Point `outputs/home-conf.nix` at the darwin profile**

Set the `mkHome` `extraSpecialArgs` to:

```nix
    extraSpecialArgs = {profile = import ../home/profiles/darwin.nix;};
```

- [ ] **Step 3: Darwin regression check (the critical one)**

Run: `nix build .#homeConfigurations.marcinwadon.activationPackage --no-link --print-out-paths`
Expected: `/nix/store/wr4s6mgg2f95g6ylmqlgs5q9379bnycq-home-manager-generation`
If the hash differs, diff the generated config against the baseline:
```bash
nix build .#homeConfigurations.marcinwadon.activationPackage --no-link --print-out-paths
# then inspect: home-files, home-path, and git config under the result
```
Common causes: `gpg.format` now explicitly set (compare `~/.config/git/config`), or an alias/ordering difference. Reconcile until the hash matches OR you've confirmed the only diff is the explicit-but-equivalent `gpg.format` line (acceptable — note the new hash in this plan).

- [ ] **Step 4: Commit**

```bash
nix fmt
git add home/profiles/darwin.nix outputs/home-conf.nix
git commit -m "refactor(home): add darwin profile reproducing macOS config"
```

---

## Task 5: Parameterize `outputs/home-conf.nix` by system, and add Linux profiles

**Files:**
- Modify: `outputs/home-conf.nix`
- Create: `home/profiles/common.nix`
- Create: `home/profiles/personal.nix`, `home/profiles/evojam.nix`, `home/profiles/parloa.nix`

- [ ] **Step 1: Make `outputs/home-conf.nix` a function of system/profile**

Replace the file with a builder that the NixOS module (Task 6) and the Darwin homeConfig both use. The key change: `system` and the neovim-flake refs are parameters, not hardcoded.

```nix
{inputs, ...}: let
  mkPkgs = system:
    import inputs.nixpkgs {
      inherit system;
      config.allowUnfree = true;
      overlays = [
        (mkFishOverlay system)
        inputs.claude-code.overlays.default
        inputs.nurpkgs.overlays.default
        inputs.neovim-flake.overlays.${system}.default
        inputs.neovim-nightly-overlay.overlays.default
      ];
    };

  mkFishOverlay = system: let
    pkgs-stable = import inputs.nixpkgs-stable {
      inherit system;
      config.allowUnfree = true;
    };
  in
    _final: _prev: {
      inherit (inputs) fish-bobthefish-theme;
      fish = pkgs-stable.fish;
    };

  mkHome = {
    system,
    profile,
  }:
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = mkPkgs system;
      extraSpecialArgs = {inherit profile;};
      modules = [
        inputs.neovim-flake.homeManagerModules.${system}.default
        ../home/home.nix
      ];
    };
in {
  # Exposed builder so the NixOS module can reuse the same module set.
  inherit mkHome mkPkgs;

  # Darwin standalone home configuration (unchanged behavior).
  homeConfigurations.marcinwadon = mkHome {
    system = "aarch64-darwin";
    profile = import ../home/profiles/darwin.nix;
  };
}
```

Implementer note: the flake currently does `homeConfigurations = import ./outputs/home-conf.nix {inherit inputs;};`. Update `flake.nix` so it reads `.homeConfigurations` from this attrset (see Task 6, Step 2). The `mkHome`/`mkPkgs` are re-exported for the NixOS layer.

- [ ] **Step 2: Create `home/profiles/common.nix`** (shared Linux profile base)

```nix
# Shared Linux profile base. Per-env profiles import & extend this.
{
  username = "marcin";
  enableConstellationScripts = false;
  enableBspCleanup = false;
  sshMatchBlocks = {};

  git = {
    userName = "Marcin Wadon";
    signing = {
      enable = true;
      format = "ssh";
      key = "/run/secrets/ssh_signing_key.pub";
      signByDefault = true;
      allowedSignersFile = "/run/secrets/allowed_signers";
    };
  };

  githubTokenFile = "/run/secrets/github_token";
}
```

- [ ] **Step 3: Create the three Linux env profiles**

`home/profiles/personal.nix`:
```nix
let
  common = import ./common.nix;
  lib = (import <nixpkgs> {}).lib or null;
in
  common
  // {
    enableConstellationScripts = true;
    enableBspCleanup = true;
    git =
      common.git
      // {
        userEmail = "PERSONAL_EMAIL_PLACEHOLDER"; # set to your personal git email
      };
  }
```

Implementer note: do NOT use `<nixpkgs>` (channel-impure). Use a plain attrset merge instead — replace the file with:
```nix
let
  common = import ./common.nix;
in
  common
  // {
    enableConstellationScripts = true;
    enableBspCleanup = true;
    git = common.git // {userEmail = "PERSONAL_EMAIL_PLACEHOLDER";};
  }
```

`home/profiles/evojam.nix`:
```nix
let
  common = import ./common.nix;
in
  common
  // {
    enableConstellationScripts = true;
    enableBspCleanup = true;
    git = common.git // {userEmail = "mwadon@evojam.com";};
  }
```

`home/profiles/parloa.nix`:
```nix
let
  common = import ./common.nix;
in
  common
  // {
    git =
      common.git
      // {
        userEmail = "244477798+marcin-wadon-parloa@users.noreply.github.com";
      };
  }
```

Implementer note: the Parloa-specific `parloa.gitconfig` (signing key, etc.) was GPG-based on the Mac; in the container Parloa identity is set directly above and signing is SSH-based, so no `extraGitconfigFiles`/`includes` are needed here.

- [ ] **Step 4: Verify Darwin still builds + profiles evaluate**

Run:
```bash
nix build .#homeConfigurations.marcinwadon.activationPackage --no-link --print-out-paths
nix eval --impure --expr '(import ./home/profiles/parloa.nix).git.userEmail'
```
Expected: Darwin hash unchanged; second command prints the Parloa email string.

- [ ] **Step 5: Commit**

```bash
nix fmt
git add outputs/home-conf.nix home/profiles/common.nix home/profiles/personal.nix home/profiles/evojam.nix home/profiles/parloa.nix
git commit -m "feat(home): parameterize home builder by system and add linux profiles"
```

---

## Task 6: Gate the Constellation/BSP scripts on the profile

The crypto network scripts (`h_mainnet`/`h_testnet`/`h_integrationnet`) and `clean-bsp-workspace` should only load when the profile enables them.

**Files:**
- Modify: `home/scripts/default.nix`

- [ ] **Step 1: Inspect the current scripts aggregator**

Run: `cat home/scripts/default.nix`
Expected: a list of script modules (similar shape to `home/programs/default.nix`).

- [ ] **Step 2: Wrap the optional scripts in a profile-gated module**

Replace `home/scripts/default.nix` so the always-on scripts (e.g. `tmux-close`) stay, and the optional ones are gated. Example shape (adapt to the actual file contents found in Step 1):

```nix
let
  gated = {
    lib,
    profile ? {},
    ...
  }: let
    defaults = import ../lib/profile-defaults.nix;
    p = lib.recursiveUpdate defaults profile;
  in {
    imports =
      lib.optionals p.enableConstellationScripts [
        ./h_mainnet.nix
        ./h_testnet.nix
        ./h_integrationnet.nix
      ]
      ++ lib.optionals p.enableBspCleanup [./clean-bsp-workspace.nix];
  };
in [
  ./tmux-close.nix
  gated
]
```

Implementer note: confirm each script file is a home-manager module that can be imported standalone. If `home/scripts/default.nix` currently `concatMap import`s them differently, mirror that mechanism. The Darwin profile sets neither toggle to `true` by default — but the Mac currently HAS these scripts. To keep the Darwin anchor stable, set `enableConstellationScripts = true; enableBspCleanup = true;` in `home/profiles/darwin.nix`.

- [ ] **Step 3: Add the toggles to the darwin profile**

In `home/profiles/darwin.nix`, add:
```nix
  enableConstellationScripts = true;
  enableBspCleanup = true;
```

- [ ] **Step 4: Darwin regression check**

Run: `nix build .#homeConfigurations.marcinwadon.activationPackage --no-link --print-out-paths`
Expected: `/nix/store/wr4s6mgg2f95g6ylmqlgs5q9379bnycq-home-manager-generation` (scripts still present on Darwin → unchanged).

- [ ] **Step 5: Commit**

```bash
nix fmt
git add home/scripts/default.nix home/profiles/darwin.nix
git commit -m "refactor(home): gate constellation/bsp scripts on profile toggles"
```

---

## Task 7: Linux GitHub-token sourcing in fish

**Files:**
- Modify: `home/programs/fish/default.nix`

- [ ] **Step 1: Inspect the fish module**

Run: `cat home/programs/fish/default.nix`
Expected: a home-manager `programs.fish` config; note whether `interactiveShellInit` / `shellInit` already exists.

- [ ] **Step 2: Add Linux-only token sourcing**

Add (merging into the existing `programs.fish` block; adapt to its actual structure) a profile/platform-gated init. At the top of the module's `let`, add:

```nix
  defaults = import ../../lib/profile-defaults.nix;
  p = lib.recursiveUpdate defaults (profile or {});
  tokenInit =
    lib.optionalString (pkgs.stdenv.isLinux && p.githubTokenFile != null) ''
      if test -r ${p.githubTokenFile}
        set -gx GITHUB_TOKEN (cat ${p.githubTokenFile})
      end
    '';
```

Ensure the module args include `lib`, `pkgs`, and `profile ? {}`. Then append `tokenInit` to the fish `interactiveShellInit` (concatenate with any existing value using `lib.concatStringsSep "\n"` or `''${existing}\n${tokenInit}''`).

- [ ] **Step 3: Darwin regression check**

Run: `nix build .#homeConfigurations.marcinwadon.activationPackage --no-link --print-out-paths`
Expected: `/nix/store/wr4s6mgg2f95g6ylmqlgs5q9379bnycq-home-manager-generation` (the added init is `isLinux`-gated, so Darwin output is unchanged).

- [ ] **Step 4: Commit**

```bash
nix fmt
git add home/programs/fish/default.nix
git commit -m "feat(home): source GITHUB_TOKEN from sops file on linux"
```

---

## Task 8: NixOS LXC base, per-env modules, and `nixosConfigurations`

**Files:**
- Create: `nixos/lxc-base.nix`
- Create: `nixos/envs/personal.nix`, `nixos/envs/evojam.nix`, `nixos/envs/parloa.nix`
- Create: `outputs/nixos-conf.nix`
- Modify: `flake.nix` (wire outputs)

- [ ] **Step 1: Create `nixos/lxc-base.nix`**

```nix
{
  config,
  lib,
  pkgs,
  modulesPath,
  inputs,
  homeModules,
  profile,
  ...
}: {
  imports = [
    "${modulesPath}/virtualisation/proxmox-lxc.nix"
    inputs.home-manager.nixosModules.home-manager
    inputs.sops-nix.nixosModules.sops
  ];

  # Unprivileged LXC; Proxmox manages networking.
  proxmoxLXC = {
    privileged = false;
    manageNetwork = false;
  };

  networking.useDHCP = lib.mkDefault true;

  time.timeZone = "Europe/Warsaw";
  i18n.defaultLocale = "en_US.UTF-8";

  nix.settings = {
    experimental-features = ["nix-command" "flakes"];
    trusted-users = ["root" "marcin"];
  };

  users.users.marcin = {
    isNormalUser = true;
    extraGroups = ["wheel"];
    shell = pkgs.fish;
    openssh.authorizedKeys.keys = [
      # TODO(provisioning): add your Mac's public SSH key here (or via a sops/extra module).
    ];
  };
  programs.fish.enable = true;
  security.sudo.wheelNeedsPassword = false;

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };

  home-manager = {
    useGlobalPkgs = false;
    useUserPackages = true;
    extraSpecialArgs = {inherit profile;};
    users.marcin = {...}: {
      imports =
        homeModules
        ++ [../home/home.nix];
    };
  };

  system.stateVersion = "24.11";
}
```

Implementer note: `homeModules` is passed in from `outputs/nixos-conf.nix` and equals `[ inputs.neovim-flake.homeManagerModules.x86_64-linux.default ]`. `useGlobalPkgs = false` lets home-manager use its own pkgs with the neovim-flake/claude-code overlays applied (see Step 3 risk handling). Cachix substituters: import the existing `../system/cachix.nix` if it is platform-neutral; otherwise add substituters inline under `nix.settings`. Verify `../system/cachix.nix` evaluates on NixOS before importing.

- [ ] **Step 2: Create the per-env NixOS modules**

`nixos/envs/personal.nix`:
```nix
{
  imports = [./../lxc-base.nix];
  networking.hostName = "personal";

  sops.defaultSopsFile = ../../secrets/personal.yaml;
  sops.age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];
  sops.secrets.github_token = {owner = "marcin";};
  sops.secrets."ssh_signing_key" = {owner = "marcin";};
  sops.secrets."ssh_signing_key.pub" = {owner = "marcin";};
  sops.secrets."allowed_signers" = {owner = "marcin";};
}
```

`nixos/envs/evojam.nix` and `nixos/envs/parloa.nix`: identical but with `hostName = "evojam"` / `"parloa"` and `defaultSopsFile = ../../secrets/evojam.yaml` / `../../secrets/parloa.yaml`.

Implementer note: `sops.age.sshKeyPaths` uses the container's SSH host key for decryption (ssh-to-age model) — no separate age key needed.

- [ ] **Step 3: Create `outputs/nixos-conf.nix`**

```nix
{inputs, ...}: let
  system = "x86_64-linux";
  homeModules = [inputs.neovim-flake.homeManagerModules.${system}.default];

  mkEnv = name: profile:
    inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = {inherit inputs homeModules profile;};
      modules = [../nixos/envs/${name}.nix];
    };
in {
  personal = mkEnv "personal" (import ../home/profiles/personal.nix);
  evojam = mkEnv "evojam" (import ../home/profiles/evojam.nix);
  parloa = mkEnv "parloa" (import ../home/profiles/parloa.nix);
}
```

Risk handling (neovim-flake / overlays on x86_64-linux): if `nix eval` in Step 5 fails inside neovim-flake or an overlay for x86_64-linux, set `homeModules = []` and remove the failing overlay from the home pkgs for Linux (gate it in `outputs/home-conf.nix`'s `mkPkgs` with `lib.optionals (system == "aarch64-darwin")` around the offending overlay), then re-run. Record which component was gated in `docs/RUNBOOK-lxc.md`.

- [ ] **Step 4: Wire `flake.nix` outputs**

In `flake.nix`, change the `outputs` block to expose the new configurations. Replace the `outputs = inputs: let ... in { ... }` body with:

```nix
  outputs = inputs: let
    darwinSystem = "aarch64-darwin";
    darwinPkgs = inputs.nixpkgs.legacyPackages.${darwinSystem};
    homeOut = import ./outputs/home-conf.nix {inherit inputs;};
  in {
    homeConfigurations = homeOut.homeConfigurations;

    darwinConfigurations = import ./outputs/darwin-conf.nix {inherit inputs;};

    nixosConfigurations = import ./outputs/nixos-conf.nix {inherit inputs;};

    formatter.${darwinSystem} = darwinPkgs.alejandra;
    formatter.x86_64-linux = inputs.nixpkgs.legacyPackages.x86_64-linux.alejandra;

    devShells.${darwinSystem}.default = darwinPkgs.mkShell {
      packages = [darwinPkgs.nix darwinPkgs.home-manager darwinPkgs.git darwinPkgs.alejandra];
      shellHook = ''
        echo "Nix development environment loaded"
      '';
    };
  };
```

Implementer note: keep the existing devShell text if preferred; the key changes are reading `homeConfigurations` from `homeOut` and adding `nixosConfigurations`.

- [ ] **Step 5: Verify — Darwin unchanged + Linux configs evaluate**

Run:
```bash
nix build .#homeConfigurations.marcinwadon.activationPackage --no-link --print-out-paths
nix eval .#nixosConfigurations.personal.config.networking.hostName
nix eval .#nixosConfigurations.parloa.config.system.build.toplevel.drvPath
```
Expected:
- Darwin hash unchanged.
- First eval prints `"personal"`.
- Second eval prints a `/nix/store/...-nixos-system-parloa-....drv` path (evaluation succeeds; build deferred to host). If this errors inside neovim-flake/overlays, apply the Step 3 risk handling.

- [ ] **Step 6: Commit**

```bash
nix fmt
git add flake.nix outputs/nixos-conf.nix nixos/
git commit -m "feat(nixos): add LXC base and personal/evojam/parloa nixosConfigurations"
```

---

## Task 9: Template package + nixos-generators output

**Files:**
- Create: `nixos/template.nix`
- Modify: `flake.nix` (add `packages.x86_64-linux.lxcTemplate`)

- [ ] **Step 1: Create `nixos/template.nix`** (minimal bootable template)

```nix
{
  pkgs,
  modulesPath,
  ...
}: {
  imports = ["${modulesPath}/virtualisation/proxmox-lxc.nix"];

  proxmoxLXC = {
    privileged = false;
    manageNetwork = false;
  };
  networking.useDHCP = true;

  nix.settings.experimental-features = ["nix-command" "flakes"];

  users.users.marcin = {
    isNormalUser = true;
    extraGroups = ["wheel"];
  };
  security.sudo.wheelNeedsPassword = false;
  services.openssh.enable = true;

  environment.systemPackages = with pkgs; [git ssh-to-age];

  system.stateVersion = "24.11";
}
```

- [ ] **Step 2: Add the `lxcTemplate` package output to `flake.nix`**

Inside the `outputs` attrset (Task 8 Step 4), add:

```nix
    packages.x86_64-linux.lxcTemplate = inputs.nixos-generators.nixosGenerate {
      system = "x86_64-linux";
      format = "proxmox-lxc";
      modules = [./nixos/template.nix];
    };
```

- [ ] **Step 3: Verify it evaluates (build deferred to host)**

Run: `nix eval .#packages.x86_64-linux.lxcTemplate.drvPath`
Expected: a `.drv` path. (Building requires x86_64-linux → done on the Proxmox host in Task 10.)

- [ ] **Step 4: Commit**

```bash
nix fmt
git add flake.nix nixos/template.nix
git commit -m "feat(nixos): add proxmox-lxc template package via nixos-generators"
```

---

## Task 10: sops scaffolding + extend `switch` + runbook

**Files:**
- Create: `secrets/.sops.yaml`
- Modify: `switch`
- Create: `docs/RUNBOOK-lxc.md`
- Modify: `.gitignore` (ensure decrypted material is never committed)

- [ ] **Step 1: Create `secrets/.sops.yaml`** (recipients filled during provisioning)

```yaml
# Recipients are per-container age keys derived from each CT's SSH host key
# (ssh-to-age). Fill <AGE_*> after the container's first boot (see RUNBOOK).
keys:
  - &personal_host age1PLACEHOLDER_PERSONAL
  - &evojam_host age1PLACEHOLDER_EVOJAM
  - &parloa_host age1PLACEHOLDER_PARLOA
creation_rules:
  - path_regex: secrets/personal\.yaml$
    key_groups: [{age: [*personal_host]}]
  - path_regex: secrets/evojam\.yaml$
    key_groups: [{age: [*evojam_host]}]
  - path_regex: secrets/parloa\.yaml$
    key_groups: [{age: [*parloa_host]}]
```

- [ ] **Step 2: Extend the `switch` script**

Add two cases to the `case $1 in` block in `switch` (before the `*)` default):

```bash
  "template")
    nix build .#packages.x86_64-linux.lxcTemplate "${@:2}"
    echo "Template built at ./result (run this on the Proxmox host)";;
  "nixos")
    if [ -z "$2" ]; then echo "Usage: $0 nixos <personal|evojam|parloa>"; exit 1; fi
    sudo nixos-rebuild switch --flake ".#$2";;
```

And update the usage text in the `*)` case to mention `template` and `nixos <env>`.

- [ ] **Step 3: Create `docs/RUNBOOK-lxc.md`**

```markdown
# Proxmox NixOS LXC — provisioning runbook

## Build the template (on the Proxmox host)
1. Install Nix on the host (Determinate installer) and enable flakes.
2. Clone this repo, then: `./switch template` (= `nix build .#packages.x86_64-linux.lxcTemplate`).
3. The artifact is at `./result/tarball/*.tar.xz`. Copy it to
   `/var/lib/vz/template/cache/` (or import via the Proxmox UI).

## Create a container (repeat per env)
- `pct create <vmid> local:vztmpl/<template>.tar.xz \
     --hostname <env> --unprivileged 1 --features nesting=1 \
     --net0 name=eth0,bridge=vmbr0,ip=dhcp --cores 4 --memory 8192 --rootfs local-lvm:32`
- Start it; add your Mac's SSH public key to `nixos/lxc-base.nix`
  (`users.users.marcin.openssh.authorizedKeys.keys`) before the first rebuild,
  or inject it via `pct push`.

## First-boot bootstrap (inside each CT)
1. `pct enter <vmid>` (or SSH in).
2. Get the age recipient from the host key:
   `nix-shell -p ssh-to-age --run 'ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub'`
3. On your workstation: paste that age key into `secrets/.sops.yaml` for this env,
   replacing the matching `age1PLACEHOLDER_*`.
4. Create the env's secrets file:
   `sops secrets/<env>.yaml`  → add keys:
   - `github_token`: a GitHub PAT for this env's account.
   - `ssh_signing_key`: a NEW ed25519 PRIVATE key (`ssh-keygen -t ed25519 -f key -N ""` → paste `key`).
   - `ssh_signing_key.pub`: the matching PUBLIC key.
   - `allowed_signers`: `<git-email> <contents-of-ssh_signing_key.pub>`
   Commit the encrypted `secrets/<env>.yaml` and the updated `.sops.yaml`.
5. Add `ssh_signing_key.pub` to this env's GitHub account as BOTH an
   Authentication key and a Signing key.
6. In the CT: clone this repo, then `./switch nixos <env>`
   (= `sudo nixos-rebuild switch --flake .#<env>`).
7. Verify: `gh auth status`, `git commit --allow-empty -m test && git log --show-signature -1`.

## Iterate
- Edit the flake, then `./switch nixos <env>` inside the CT.
```

- [ ] **Step 4: Ensure decrypted secrets can't be committed**

Append to `.gitignore`:
```
# decrypted sops material / generated keys
*.dec
key
secrets/*.plain
result
```

- [ ] **Step 5: Verify the switch script parses and template still evaluates**

Run:
```bash
bash -n switch && echo "switch OK"
nix eval .#packages.x86_64-linux.lxcTemplate.drvPath
```
Expected: `switch OK`; a `.drv` path.

- [ ] **Step 6: Commit**

```bash
nix fmt
git add secrets/.sops.yaml switch docs/RUNBOOK-lxc.md .gitignore
git commit -m "feat(nixos): add sops scaffolding, switch subcommands, and LXC runbook"
```

---

## Task 11: Build + provision on the Proxmox host (manual, off the Mac)

These steps run on the x86_64 Proxmox host / inside the CTs and cannot be verified from the aarch64 Mac. Follow `docs/RUNBOOK-lxc.md`.

- [ ] **Step 1:** Install Nix on the Proxmox host; `./switch template`; confirm `./result/tarball/*.tar.xz` exists.
- [ ] **Step 2:** Upload template; `pct create` the `personal` container; start it.
- [ ] **Step 3:** Bootstrap sops for `personal` (host key → age recipient → `sops secrets/personal.yaml` → commit), add signing pubkey to GitHub.
- [ ] **Step 4:** Inside the CT: `./switch nixos personal`. Expected: rebuild succeeds; `/run/secrets/github_token` exists (mode 0400, owner marcin).
- [ ] **Step 5:** Verify: `gh auth status` authenticated; `git commit --allow-empty -m sig-test && git log --show-signature -1` shows a good SSH signature.
- [ ] **Step 6:** Repeat Steps 2–5 for `evojam` and `parloa` when ready.

---

## Self-review notes

- **Spec coverage:** structure (§Architecture)→Tasks 5/8/9; platform-aware refactor (§2)→Tasks 2/3; LXC base+provisioning (§3)→Tasks 8/9/10/11; sops+signing (§4)→Tasks 3/7/8/10; profiles/toolchains/workflow (§5)→Tasks 1/5/6/10. Darwin-frozen guarantee→Tasks 0/2/4/5/6/7 regression anchor.
- **Toolchains:** "minimal global + per-project direnv" → Linux profiles add no SDKs (`extraPackages` default `[]`); direnv already enabled in `programs/default.nix`. ✓
- **Type consistency:** profile fields (`username`, `git.userName/userEmail/signing.{enable,format,key,signByDefault,allowedSignersFile}`, `git.includes`, `git.extraGitconfigFiles`, `extraPackages`, `enableConstellationScripts`, `enableBspCleanup`, `sshMatchBlocks`, `githubToken`, `githubTokenFile`) are defined once in Task 1 and read identically in Tasks 2/3/6/7. ✓
- **Secrets hygiene:** no real tokens/keys are committed; `secrets/*.yaml` are created encrypted during provisioning (Task 10/11); `.gitignore` guards decrypted material. ✓
- **Known risk:** neovim-flake/overlays on x86_64-linux — explicit fallback in Task 8 Step 3.
```
