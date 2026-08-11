{
  description = "my nixos config";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";

    # Stable nixpkgs for packages that break on unstable
    nixpkgs-stable.url = "nixpkgs/nixos-25.05";

    # nixpkgs pinned before nodePackages removal (2026-03-03) for neovim-flake
    nixpkgs-pre-nodepackages.url = "github:NixOS/nixpkgs/a82ccc39b39b621151d6732718e3e250109076fa";

    darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nurpkgs = {
      url = "github:nix-community/NUR";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    neovim-flake = {
      url = "github:gvolpe/neovim-flake";
      # neovim-flake internally uses pkgs.nodePackages (removed 2026-03-03);
      # pin its nixpkgs to a version that still has nodePackages
      inputs.nixpkgs.follows = "nixpkgs-pre-nodepackages";
    };

    fish-bobthefish-theme = {
      url = "github:gvolpe/theme-bobthefish";
      flake = false;
    };

    nix-search = {
      url = "github:diamondburned/nix-search";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    neovim-nightly-overlay = {
      url = "github:nix-community/neovim-nightly-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    claude-code = {
      url = "github:sadjow/claude-code-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Private repo — fetched via nix's github fetcher. Locking (here) and the
    # builder both need a token: `--option access-tokens github.com=<ghp_…>`
    # (or an access-tokens line in nix.conf). See docs/RUNBOOK-lxc.md.
    claude-monitor = {
      url = "github:marcinwadon/claude-monitor";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Terminal multiplexer for coding agents (Rust). Pinned to a release tag
    # per upstream's recommendation. Deliberately NOT `follows`-ing nixpkgs:
    # herdr builds on its own locked nixpkgs + the rust-overlay toolchain pinned
    # via its rust-toolchain.toml — following would risk a toolchain mismatch.
    # Consumed as `pkgs.herdr` via a package-ref overlay (see outputs/home-conf.nix),
    # NOT its `overlays.default` (which composes in the whole rust-overlay).
    herdr = {
      url = "github:ogulcancelik/herdr/v0.7.5";
    };
  };

  outputs = {self, ...} @ inputs: let
    system = "aarch64-darwin";
    pkgs = inputs.nixpkgs.legacyPackages.${system};
  in {
    homeConfigurations = (import ./outputs/home-conf.nix {inherit inputs;}).homeConfigurations;

    darwinConfigurations = import ./outputs/darwin-conf.nix {inherit inputs;};

    nixosConfigurations = import ./outputs/nixos-conf.nix {inherit inputs;};

    # checks.${system} is a single dynamic-attribute-path binding: `${system}`
    # is computed, so (unlike a literal identifier) Nix cannot merge two
    # separate `checks.${system}.foo = ...;`/`checks.${system}.bar = ...;`
    # bindings in one attrset literal ("dynamic attribute ... already
    # defined") — both checks below must live under one `checks.${system} =
    # { ... };` assignment.
    checks.${system} = {
      # Guard: fail `nix flake check` if any Linux container's fish config
      # leaks a GitHub token literal or runs the gpg-agent (gpgconf) — the
      # class of bug a code review caught earlier. Eval-only over the
      # x86_64-linux configs, so it runs on the darwin build host without a
      # Linux builder.
      #
      # minRenderLen is a tripwire against a VACUOUS pass: `hits == []` is
      # also true if `rendered` is empty (an option rename, a Linux/Darwin
      # branch, a module going unimported would all silently zero out
      # programs.fish). A real render is ~1.4-2.5k chars per config; 200 is
      # comfortably below every real config and comfortably above the
      # handful of newline separators a broken/empty render would produce.
      # Checked separately per group so one group going empty can't hide
      # behind the other's real content.
      no-linux-secret-leak = let
        lib = inputs.nixpkgs.lib;
        forbidden = ["ghp_" "ghs_" "github_pat_" "gpgconf"];
        minRenderLen = 200;
        renderFish = f: (f.shellInit or "") + "\n" + (f.interactiveShellInit or "");
        renderedNixos = lib.concatMapStringsSep "\n" (e:
          renderFish self.nixosConfigurations.${e}.config.home-manager.users.marcin.programs.fish)
        ["personal" "evojam" "parloa" "monitor"];
        renderedM1 = lib.concatMapStringsSep "\n" (c:
          renderFish self.homeConfigurations.${c}.config.programs.fish)
        ["m1-personal" "m1-evojam" "m1-parloa"];
        rendered = renderedNixos + "\n" + renderedM1;
        hits = lib.filter (p: lib.hasInfix p rendered) forbidden;
      in
        if builtins.stringLength renderedNixos < minRenderLen
        then throw "no-linux-secret-leak: nixos fish render is suspiciously short (${toString (builtins.stringLength renderedNixos)} chars, expected >= ${toString minRenderLen}) — this check would otherwise pass VACUOUSLY; investigate before trusting a clean result"
        else if builtins.stringLength renderedM1 < minRenderLen
        then throw "no-linux-secret-leak: m1 fish render is suspiciously short (${toString (builtins.stringLength renderedM1)} chars, expected >= ${toString minRenderLen}) — this check would otherwise pass VACUOUSLY; investigate before trusting a clean result"
        else if hits == []
        then pkgs.runCommand "no-linux-secret-leak" {} "echo ok > $out"
        else throw "SECRET LEAK in linux fish config — matched: ${toString hits}";

      # Guard: the three M1 home configurations have no sops-nix, so unlike
      # the nixos configs (which legitimately reference /run/secrets
      # everywhere — this string can't join the check above's `forbidden`
      # list), a /run/secrets path surviving into an M1 config's rendered
      # ssh or git settings is ALWAYS a bug: home/profiles/m1-common.nix
      # exists solely to repoint every such path at a real file under the
      # user's home. Renders (not option paths) because a rendered artifact
      # is what actually reaches disk — see home/profiles/m1-common.nix for
      # the two override styles this regression-guards. minRenderLen is the
      # same vacuous-pass tripwire as above (real per-client render is
      # ~1.7-1.8k chars; checked per-client so one client silently going
      # empty can't hide behind the other two).
      no-m1-secret-leak = let
        lib = inputs.nixpkgs.lib;
        clients = ["m1-personal" "m1-evojam" "m1-parloa"];
        minRenderLen = 200;
        renderClient = c: let
          cfg = self.homeConfigurations.${c}.config;
          sshText = cfg.home.file.".ssh/config".text or "";
          gitJson = builtins.toJSON cfg.programs.git.settings;
        in
          sshText + "\n" + gitJson;
        rendered = lib.genAttrs clients renderClient;
        tooShort = lib.filterAttrs (_c: t: builtins.stringLength t < minRenderLen) rendered;
        leaking = lib.filterAttrs (_c: t: lib.hasInfix "/run/secrets" t) rendered;
      in
        if tooShort != {}
        then throw "no-m1-secret-leak: rendered ssh+git config suspiciously short for: ${toString (builtins.attrNames tooShort)} — this check would otherwise pass VACUOUSLY; investigate before trusting a clean result"
        else if leaking != {}
        then throw "SECRET LEAK: /run/secrets found in the rendered ssh/git config for: ${toString (builtins.attrNames leaking)} — this box has no sops-nix, so an inherited default is a silent regression, not a benign one"
        else pkgs.runCommand "no-m1-secret-leak" {} "echo ok > $out";
    };

    packages.x86_64-linux.lxcTemplate = inputs.nixos-generators.nixosGenerate {
      system = "x86_64-linux";
      format = "proxmox-lxc";
      modules = ["${self}/nixos/template.nix"];
    };

    formatter.x86_64-linux = inputs.nixpkgs.legacyPackages.x86_64-linux.alejandra;

    formatter.${system} = pkgs.alejandra;

    devShells.${system} = {
      default = pkgs.mkShell {
        packages = [
          pkgs.nix
          pkgs.home-manager
          pkgs.git
          pkgs.alejandra
        ];
        shellHook = ''
          echo "Nix development environment loaded"
          echo "Available commands:"
          echo "  ./switch home    - rebuild home configuration"
          echo "  ./switch darwin  - rebuild system configuration"
          echo "  nix flake update - update flake inputs"
          echo "  nix flake check  - check flake for issues"
        '';
      };
    };
  };
}
