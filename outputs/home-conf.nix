{inputs, ...}: let
  system = "aarch64-darwin";

  # Use stable fish version (4.0.x) from nixpkgs-stable instead of unstable (4.2.x)
  pkgs-stable = import inputs.nixpkgs-stable {
    inherit system;
    config.allowUnfree = true;
  };

  fishOverlay = _final: _prev: {
    inherit (inputs) fish-bobthefish-theme;
    fish = pkgs-stable.fish;
  };

  pkgs = import inputs.nixpkgs {
    inherit system;
    config.allowUnfree = true;
    overlays = [
      fishOverlay
      inputs.claude-code.overlays.default
      inputs.nurpkgs.overlays.default
      inputs.neovim-flake.overlays.${system}.default
      inputs.neovim-nightly-overlay.overlays.default
    ];
  };

  mkHome = inputs.home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    extraSpecialArgs = {profile = import ../home/profiles/darwin.nix;};
    modules = [
      inputs.neovim-flake.homeManagerModules.${system}.default
      ../home/home.nix
    ];
  };
in {
  marcinwadon = mkHome;
}
