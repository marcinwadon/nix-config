{
  config,
  pkgs,
  ...
}: let
  plugins = pkgs.callPackage ./plugins.nix {};

  # Darwin: full config + "custom" layout (status bar with session+datetime,
  # pane frames). Linux containers: trimmed config-linux.kdl + "minimal" layout
  # (thin mode+tabs bar, no borders).
  configFiles =
    if pkgs.stdenv.isDarwin
    then {
      "zellij/config.kdl".source = ./config.kdl;
      "zellij/layouts/custom.kdl".source = ./layout.kdl;
    }
    else {
      "zellij/config.kdl".source = ./config-linux.kdl;
      "zellij/layouts/minimal.kdl".source = ./minimal.kdl;
    };
in {
  programs.zellij = {
    enable = true;
    enableFishIntegration = false;
  };

  xdg.configFile =
    configFiles
    // {
      "zellij/plugins/zellij-autolock.wasm".source = plugins.zellij-autolock;
      "zellij/plugins/zjstatus.wasm".source = plugins.zjstatus;
      "zellij/plugins/ghost.wasm".source = plugins.ghost;
      "zellij/plugins/harpoon.wasm".source = plugins.harpoon;
      "zellij/plugins/zellij-choose-tree.wasm".source = plugins.zellij-choose-tree;
    };
}
