{pkgs, ...}: let
  buildTmuxPlugin = pkgs.tmuxPlugins.mkTmuxPlugin;
in {
  nord = buildTmuxPlugin {
    pluginName = "nord";
    version = "v0.3.0";
    src = pkgs.fetchFromGitHub {
      owner = "arcticicestudio";
      repo = "nord-tmux";
      rev = "4e2dc2a5065f5e8e67366700f803c733682e8f8c";
      hash = "sha256-ihh0wgH4SjceaHtwcV7OyM11lnNhTCWTOS4MbBdmJ1E=";
    };
  };
}
