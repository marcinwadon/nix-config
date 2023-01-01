{ config, lib, pkgs, stdenv, ... }:

let
  username = "marcin";
  homeDirectory = "/home/${username}";
  configHome = "${homeDirectory}/.config";

  defaultPkgs = with pkgs; [
    any-nix-shell
    asciinema
    bottom
    # cachix
    dig
    duf
    exa
    fd
    killall
    lnav
    ncdu
    nyancat
    prettyping
    ripgrep
    tldr
    tree
  ];
in
{
  programs.home-manager.enable = true;

  imports = builtins.concatMap import [
    ./programs
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
