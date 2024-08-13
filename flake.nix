{
  description = "my nixos config";

  inputs = {
    #nixpkgs.url = "nixpkgs/23.05";
    nixpkgs.url = "nixpkgs/nixos-unstable";

    darwin = {
      url = github:LnL7/nix-darwin;
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nurpkgs.url = github:nix-community/NUR;

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
  };

  outputs = inputs: {
    homeConfigurations = (
      import ./outputs/home-conf.nix {
        inherit inputs;
      }
    );
    nixosConfigurations = (
      import ./outputs/nixos-conf.nix {
        inherit inputs;
      }
    );
    darwinConfigurations = (
      import ./outputs/darwin-conf.nix {
        inherit inputs;
      }
    );
  };
}
