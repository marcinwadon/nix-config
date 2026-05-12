{
  config,
  lib,
  pkgs,
  darwin,
  ...
}: let
  username = "marcinwadon";
  homeDirectory = "/Users/${username}";

  defaultPkgs = [
    pkgs.alejandra
    pkgs.any-nix-shell
    pkgs.oxfmt
    pkgs.oxlint
    pkgs.asciinema
    pkgs.bottom
    pkgs.cachix
    pkgs.claude-code
    pkgs.dig
    pkgs.duf
    pkgs.eza
    pkgs.fd
    pkgs.gh
    pkgs.killall
    pkgs.lnav
    pkgs.mosh
    pkgs.ncdu
    pkgs.nyancat
    pkgs.nix-index
    pkgs.nix-output-monitor
    pkgs.pinentry_mac
    pkgs.prettyping
    pkgs.ripgrep
    pkgs.tldr
    pkgs.tree
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
      pinentry-program ${pkgs.pinentry_mac}/Applications/pinentry-mac.app/Contents/MacOS/pinentry-mac
      enable-ssh-support
      default-cache-ttl 28800
      max-cache-ttl 28800
    '';
  };
}
