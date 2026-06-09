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
  };

  outputs = {self, ...} @ inputs: let
    system = "aarch64-darwin";
    pkgs = inputs.nixpkgs.legacyPackages.${system};
  in {
    homeConfigurations = (import ./outputs/home-conf.nix {inherit inputs;}).homeConfigurations;

    darwinConfigurations = import ./outputs/darwin-conf.nix {inherit inputs;};

    nixosConfigurations = import ./outputs/nixos-conf.nix {inherit inputs;};

    # Guard: fail `nix flake check` if any Linux container's fish config leaks a
    # GitHub token literal or runs the gpg-agent (gpgconf) — the class of bug a
    # code review caught earlier. Eval-only over the x86_64-linux configs, so it
    # runs on the darwin build host without a Linux builder.
    checks.${system}.no-linux-secret-leak = let
      lib = inputs.nixpkgs.lib;
      forbidden = ["ghp_" "ghs_" "github_pat_" "gpgconf"];
      rendered = lib.concatMapStringsSep "\n" (e: let
        f = self.nixosConfigurations.${e}.config.home-manager.users.marcin.programs.fish;
      in
        (f.shellInit or "") + "\n" + (f.interactiveShellInit or ""))
      ["personal" "evojam" "parloa" "monitor"];
      hits = lib.filter (p: lib.hasInfix p rendered) forbidden;
    in
      if hits == []
      then pkgs.runCommand "no-linux-secret-leak" {} "echo ok > $out"
      else throw "SECRET LEAK in linux fish config — matched: ${toString hits}";

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
