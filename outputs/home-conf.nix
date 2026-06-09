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

  # neovim overlays override pkgs.neovim with neovim-flake's source-built nvim,
  # which can't build on Linux (crates.io blocks the pinned old nixpkgs's
  # cargo-vendor User-Agent). Darwin-only; Linux uses stock nixpkgs neovim.
  mkOverlays = system:
    [
      (mkFishOverlay system)
      inputs.claude-code.overlays.default
      inputs.nurpkgs.overlays.default
      # claude-monitor collector+hook (built from the marcinwadon/claude-monitor flake)
      (_final: _prev: {
        claude-monitor = inputs.claude-monitor.packages.${system}.default;
      })
    ]
    ++ inputs.nixpkgs.lib.optionals (system == "aarch64-darwin") [
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
