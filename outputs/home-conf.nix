{inputs, ...}:
with inputs; let
  fishOverlay = f: p: {
    inherit fish-bobthefish-theme;
  };

  neovimOverlay = neovim-nightly-overlay.overlays.default;

  pkgs = import nixpkgs {
    system = "aarch64-darwin";
    config.allowUnfree = true;

    overlays = [
      fishOverlay
      nurpkgs.overlays.default
      neovim-flake.overlays.aarch64-darwin.default
      neovimOverlay
    ];
  };

  mkHome = home-manager.lib.homeManagerConfiguration {
    inherit pkgs;

    extraSpecialArgs = {
      darwin = true;
    };

    modules = [
      neovim-flake.homeManagerModules.aarch64-darwin.default
      ../home/home.nix
    ];
  };
in {
  marcinwadon = mkHome;
}
