{
  config,
  lib,
  pkgs,
  profile ? {},
  ...
}: let
  defaults = import ./lib/profile-defaults.nix;
  p = lib.recursiveUpdate defaults profile;

  username = p.username;
  homeDirectory =
    if pkgs.stdenv.isDarwin
    then "/Users/${username}"
    else "/home/${username}";

  defaultPkgs =
    [
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
    ]
    ++ lib.optionals pkgs.stdenv.isDarwin [pkgs.pinentry_mac]
    ++ lib.optionals pkgs.stdenv.isLinux [pkgs.pinentry-curses]
    ++ [
      pkgs.prettyping
      pkgs.ripgrep
      pkgs.tldr
      pkgs.tree
    ]
    ++ (p.extraPackages pkgs);
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

    sessionVariables =
      {EDITOR = "nvim";}
      // lib.optionalAttrs (p.githubToken != null) {
        GITHUB_TOKEN = p.githubToken;
      };

    # Darwin-only: pinentry-mac path + GPG agent SSH support.
    file = lib.optionalAttrs pkgs.stdenv.isDarwin {
      ".gnupg/gpg-agent.conf".text = ''
        pinentry-program ${pkgs.pinentry_mac}/Applications/pinentry-mac.app/Contents/MacOS/pinentry-mac
        enable-ssh-support
        default-cache-ttl 28800
        max-cache-ttl 28800
      '';
    };
  };
}
