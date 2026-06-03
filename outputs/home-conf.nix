{inputs, ...}: let
  mkFishOverlay = system: let
    pkgs-stable = import inputs.nixpkgs-stable {
      inherit system;
      config.allowUnfree = true;
    };
  in
    _final: _prev: {
      inherit (inputs) fish-bobthefish-theme;
      fish = pkgs-stable.fish;
    };

  mkOverlays = system: [
    (mkFishOverlay system)
    inputs.claude-code.overlays.default
    inputs.nurpkgs.overlays.default
    inputs.neovim-flake.overlays.${system}.default
    inputs.neovim-nightly-overlay.overlays.default
  ];

  mkPkgs = system:
    import inputs.nixpkgs {
      inherit system;
      config.allowUnfree = true;
      overlays = mkOverlays system;
    };

  mkHome = {
    system,
    profile,
  }:
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = mkPkgs system;
      extraSpecialArgs = {inherit profile;};
      modules = [
        inputs.neovim-flake.homeManagerModules.${system}.default
        ../home/home.nix
      ];
    };
in {
  # Exposed builders so the NixOS layer can reuse the same module set.
  inherit mkHome mkPkgs mkOverlays;

  # Darwin standalone home configuration (unchanged behavior).
  homeConfigurations.marcinwadon = mkHome {
    system = "aarch64-darwin";
    profile = import ../home/profiles/darwin.nix;
  };
}
