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
      # claude-monitor packages (built from the marcinwadon/claude-monitor flake).
      # Split: `claude-monitor` (collector, embeds the React UI) vs
      # `claude-monitor-hook` (hook only, no frontend build) — hook machines use
      # the latter so they never build the Vite app.
      (_final: _prev: {
        claude-monitor = inputs.claude-monitor.packages.${system}.claude-monitor;
        claude-monitor-hook = inputs.claude-monitor.packages.${system}.claude-monitor-hook;
        # The ACP adapter the per-machine host spawns (Zed's claude-code-acp).
        claude-code-acp = inputs.claude-monitor.packages.${system}.claude-code-acp;
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
