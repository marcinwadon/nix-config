{
  description = "my nixos config";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";

    nurpkgs.url = github:nix-community/NUR;

    home-manager = {
      url = github:nix-community/home-manager;
      inputs.nixpkgs.follows = "nixpkgs";
    };

    neovim-flake = {
      url = github:gvolpe/neovim-flake;
    };

    fish-bobthefish-theme = {
      url = github:gvolpe/theme-bobthefish;
      flake = false;
    };
  };

  outputs = inputs:
    let system = "x86_64-linux"; in
    {
      homeConfigurations = (
        import ./outputs/home-conf.nix {
          inherit inputs system;
        }
      );
      nixosConfigurations = (
        import ./outputs/nixos-conf.nix {
          inherit inputs system;
        }
      );
    };
}

