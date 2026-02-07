{
  config,
  pkgs,
  ...
}: let
  plugins = pkgs.callPackage ./plugins.nix {};
in {
  programs.zellij = {
    enable = true;
    enableFishIntegration = false;
  };

  xdg.configFile = {
    "zellij/config.kdl".source = ./config.kdl;
    "zellij/layouts/custom.kdl".source = ./layout.kdl;

    "zellij/plugins/zellij-autolock.wasm".source = plugins.zellij-autolock;
    "zellij/plugins/zjstatus.wasm".source = plugins.zjstatus;
    "zellij/plugins/ghost.wasm".source = plugins.ghost;
    "zellij/plugins/harpoon.wasm".source = plugins.harpoon;
    "zellij/plugins/zellij-choose-tree.wasm".source = plugins.zellij-choose-tree;
    "zellij/plugins/zellij-sessionizer.wasm".source = plugins.zellij-sessionizer;
  };
}
