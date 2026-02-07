{
  config,
  lib,
  pkgs,
  stdenv,
  darwin,
  ...
}: let
  username = "marcinwadon";
  homeDirectory = "/Users/${username}";
  configHome = "${homeDirectory}/.config";

  defaultPkgs = with pkgs; [
    alejandra
    any-nix-shell
    asciinema
    bottom
    cachix
    claude-code
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
    pinentry-curses
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
    stateVersion = "24.11";

    packages = defaultPkgs;

    sessionVariables = {
      EDITOR = "nvim";
      GITHUB_TOKEN = import ./secrets/github;
    };

    file.".gnupg/gpg-agent.conf".text = ''
      pinentry-program ${pkgs.pinentry-curses}/bin/pinentry-curses
      enable-ssh-support
      default-cache-ttl 28800
      max-cache-ttl 28800
    '';
  };
}
