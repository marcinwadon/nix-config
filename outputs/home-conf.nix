{ inputs, ... }:

with inputs;

let
  fishOverlay = f: p: {
    inherit fish-bobthefish-theme;
  };

  pkgs = { darwin }: import nixpkgs {
    system = if darwin then "aarch64-darwin" else "x86_64-linux";

    config.allowUnfree = true;

    overlays = [
      fishOverlay
      nurpkgs.overlay
      neovim-flake.overlays.${if darwin then "aarch64-darwin" else "x86_64-linux"}.default
    ];
  };

  nur = { darwin }: import nurpkgs {
    inherit pkgs;
    nurpkgs = pkgs;
  };

  imports = { darwin }: [
    neovim-flake.nixosModules.${if darwin then "aarch64-darwin" else "x86_64-linux"}.hm
    ../home/home.nix
  ];

  mkHome = { darwin ? false }: (
    home-manager.lib.homeManagerConfiguration {
      pkgs = pkgs { inherit darwin; };

      extraSpecialArgs = {
        inherit darwin;
      };

      modules = [{ imports = imports { inherit darwin; }; }];
    }
  );
in
{
  marcin-nixos = mkHome { darwin = false; };
  marcin-macos = mkHome { darwin = true; };
}
