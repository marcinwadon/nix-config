{ inputs, ... }:

with inputs;

let
  fishOverlay = f: p: {
    inherit fish-bobthefish-theme;
  };

  neovimOverlay = 
    import (
      let
        rev = "c57746e2b9e3b42c0be9d9fd1d765f245c3827b7";
      in
      builtins.fetchTarball {
        url = "https://github.com/nix-community/neovim-nightly-overlay/archive/${rev}.tar.gz";
        sha256 = "0xp4hm5hjg1vpkjz9p3i1j13jd71snkw270gi3jwwbcid86z398a";
      }
    );
  

  pkgs = { darwin }: import nixpkgs {
    system = if darwin then "aarch64-darwin" else "x86_64-linux";

    config.allowUnfree = true;

    overlays = [
      fishOverlay
      nurpkgs.overlay
      neovim-flake.overlays.${if darwin then "aarch64-darwin" else "x86_64-linux"}.default
      neovimOverlay
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
  marcinwadon = mkHome { darwin = true; };
}
