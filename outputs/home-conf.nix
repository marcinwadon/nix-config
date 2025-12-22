{inputs, ...}:
with inputs; let
  # Use stable fish version (4.0.x) from nixpkgs-stable instead of unstable (4.2.x)
  pkgs-stable = import nixpkgs-stable {
    system = "aarch64-darwin";
    config.allowUnfree = true;
  };

  fishOverlay = f: p: {
    inherit fish-bobthefish-theme;
    fish = pkgs-stable.fish;
  };

  neovimOverlay = neovim-nightly-overlay.overlays.default;

  pkgs = import nixpkgs {
    system = "aarch64-darwin";
    config.allowUnfree = true;

    overlays = [
      fishOverlay
      claude-code.overlays.default
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
