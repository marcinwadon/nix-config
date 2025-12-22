{
  description = "my nixos config";

  inputs = {
    #nixpkgs.url = "nixpkgs/24.05";
    nixpkgs.url = "nixpkgs/nixos-unstable";
    #nixpkgs.url = "git+https://github.com/NixOS/nixpkgs?shallow=1&ref=nixos-unstable";

    # Stable nixpkgs for packages that break on unstable
    nixpkgs-stable.url = "nixpkgs/nixos-24.05";

    darwin = {
      url = github:LnL7/nix-darwin;
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nurpkgs = {
      url = github:nix-community/NUR;
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = github:nix-community/home-manager;
      inputs.nixpkgs.follows = "nixpkgs";
    };

    neovim-flake = {
      url = github:gvolpe/neovim-flake;
      inputs.nixpkgs.follows = "nixpkgs";
    };

    fish-bobthefish-theme = {
      url = github:gvolpe/theme-bobthefish;
      flake = false;
    };

    nix-search = {
      url = github:diamondburned/nix-search;
      inputs.nixpkgs.follows = "nixpkgs";
    };

    neovim-nightly-overlay = {
      url = github:nix-community/neovim-nightly-overlay;
      inputs.nixpkgs.follows = "nixpkgs";
    };

    claude-code = {
      url = "github:sadjow/claude-code-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs: let
    system = "aarch64-darwin";
    pkgs = inputs.nixpkgs.legacyPackages.${system};
  in {
    homeConfigurations = (
      import ./outputs/home-conf.nix {
        inherit inputs;
      }
    );
    
    darwinConfigurations = (
      import ./outputs/darwin-conf.nix {
        inherit inputs;
      }
    );

    formatter.${system} = pkgs.alejandra;

    devShells.${system} = {
      default = pkgs.mkShell {
        buildInputs = with pkgs; [
          nix
          home-manager
          git
          alejandra
        ];
        shellHook = ''
          echo "Nix development environment loaded"
          echo "Available commands:"
          echo "  ./switch home   - rebuild home configuration"
          echo "  ./switch darwin - rebuild system configuration"
          echo "  nix flake update - update flake inputs"
          echo "  nix flake check  - check flake for issues"
        '';
      };
    };
  };
}
