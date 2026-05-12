let
  scripts = {
    config,
    lib,
    pkgs,
    ...
  }: let
    clean-bsp-workspace = pkgs.callPackage ./clean-bsp-workspace.nix {};
    tmux-close = pkgs.callPackage ./tmux-close.nix {};
    mainnet = pkgs.callPackage ./h_mainnet.nix {};
    testnet = pkgs.callPackage ./h_testnet.nix {};
    integrationnet = pkgs.callPackage ./h_integrationnet.nix {};
  in {
    home.packages = [
      clean-bsp-workspace
      tmux-close
      mainnet
      testnet
      integrationnet
    ];
  };
in [scripts]
