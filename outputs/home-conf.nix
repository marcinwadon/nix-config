{ inputs, system, ... }:

with inputs;

let
  fishOverlay = f: p: {
    inherit fish-bobthefish-theme;
  };

  pkgs = import nixpkgs {
    inherit system;

    config.allowUnfree = true;

    overlays = [
      fishOverlay
      nurpkgs.overlay
      neovim-flake.overlays.${system}.default
    ];
  };

  nur = import nurpkgs {
    inherit pkgs;
    nurpkgs = pkgs;
  };

  imports = [
    neovim-flake.nixosModules.${system}.hm
    ../home/home.nix
  ];

  mkHome = { hidpi ? false }: (
    home-manager.lib.homeManagerConfiguration {
      inherit pkgs;

      extraSpecialArgs = {
        inherit hidpi;
      };

      modules = [{ inherit imports; }];
    }
  );
in
{
  marcin-edp = mkHome { hidpi = false; };
}
