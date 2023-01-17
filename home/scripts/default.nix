let
  scripts = { config, lib, pkgs, ... }:
  let
      clean-bsp-workspace = pkgs.callPackage ./clean-bsp-workspace.nix { inherit pkgs; };
      tmux-close = pkgs.callPackage ./tmux-close.nix { inherit pkgs; };
      mainnet = pkgs.callPackage ./h_mainnet.nix { inherit pkgs; };
      testnet = pkgs.callPackage ./h_testnet.nix { inherit pkgs; };
    in
      {
        home.packages = [
          clean-bsp-workspace
          tmux-close
          mainnet
          testnet
        ];
      };
in
[ scripts ]
