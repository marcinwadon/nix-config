let
  more = {
    pkgs,
    lib,
    profile ? {},
    ...
  }: let
    defaults = import ../lib/profile-defaults.nix;
    p = lib.recursiveUpdate defaults profile;
  in {
    programs = {
      bat.enable = true;

      broot = {
        enable = true;
        enableFishIntegration = true;
      };

      direnv = {
        enable = true;
        nix-direnv.enable = true;
      };

      fzf = {
        enable = true;
        enableFishIntegration = true;
        defaultCommand = "fd --type file --follow";
        defaultOptions = ["--height 20%"];
        fileWidgetCommand = "fd --type file --follow";
      };

      # GPG + Yubikey scdaemon: Darwin only (containers sign over SSH, secrets via sops).
      gpg = lib.mkIf pkgs.stdenv.isDarwin {
        enable = true;
        publicKeys = [
          {
            source = ../../public.gpg;
            trust = "ultimate";
          }
        ];
        scdaemonSettings = {
          reader-port = "Yubico Yubi";
          disable-ccid = true;
        };
      };

      htop = {
        enable = true;
        settings = {
          sort_direction = true;
          sort_key = "PERCENT_CPU";
        };
      };

      jq.enable = true;

      ssh = {
        enable = true;
        matchBlocks =
          if pkgs.stdenv.isDarwin
          then import ../secrets/ssh.nix
          else p.sshMatchBlocks;
      };
    };
  };
in [
  ./git
  ./fish
  ./tmux
  ./zellij
  ./neovim-ide
  ./claude-code
  more
]
