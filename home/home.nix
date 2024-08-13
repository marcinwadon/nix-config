{
  config,
  lib,
  pkgs,
  stdenv,
  darwin,
  ...
}: let
  username =
    if darwin
    then "marcinwadon"
    else "marcin";
  homeDirectory =
    if darwin
    then "/Users/${username}"
    else "/home/${username}";
  configHome = "${homeDirectory}/.config";

  defaultPkgs = with pkgs; [
    alejandra
    any-nix-shell
    asciinema
    bottom
    cachix
    dig
    duf
    eza
    fd
    gh
    killall
    lnav
    ncdu
    nyancat
    nix-index
    nix-output-monitor
    nix-search
    prettyping
    ripgrep
    tldr
    tree
  ];
in {
  programs.home-manager.enable = true;

  imports = builtins.concatMap import [
    ./programs
    ./scripts
  ];

  home = {
    inherit username homeDirectory;
    stateVersion = "23.05";

    packages = defaultPkgs;

    sessionVariables = {
      EDITOR = "nvim";
    };
  };
}
