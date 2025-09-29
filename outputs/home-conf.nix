{inputs, ...}:
with inputs; let
  fishOverlay = f: p: {
    inherit fish-bobthefish-theme;
  };

  claudeCodeOverlay = final: prev: {
    claude-code = prev.claude-code.overrideAttrs (oldAttrs: rec {
      version = "2.0.0";
      src = prev.fetchzip {
        url = "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-${version}.tgz";
        hash = "sha256-uHU9SZso0OZkbcroaVqqVoDvpn28rZVc6drHBrElt5M=";
      };
      # Using the same npmDepsHash from 1.0.126 - may need updating if dependencies changed
      npmDepsHash = "sha256-m+GYa3uPfkUDV+p95uQToY3n/k0JG8hbppBn0GUeV+8=";
    });
  };

  neovimOverlay = neovim-nightly-overlay.overlays.default;

  pkgs = import nixpkgs {
    system = "aarch64-darwin";
    config.allowUnfree = true;

    overlays = [
      fishOverlay
      claudeCodeOverlay
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
