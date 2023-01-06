let
  more = { pkgs, ...}: {
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
        defaultOptions = [ "--height 20%" ];
        fileWidgetCommand = "fd --type file --follow";
      };

      gpg = {
        enable = true;
        publicKeys = [ {
          source = ../../public.gpg;
          trust = "ultimate";
        } ];
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
        forwardAgent = true;
#        startAgent = false;
        matchBlocks = {
          "dev" = {
            hostname = "10.0.1.170";
            user = "marcin";
            forwardAgent = true;
            remoteForwards = [
              {
                bind.address = "/home/marcin/.gnupg/S.gpg-agent";
                host.address = "/Users/marcinwadon/.gnupg/S.gpg-agent.extra";
              }
              {
                bind.address = "/run/user/1000/gnupg/S.gpg-agent";
                host.address = "/Users/marcinwadon/.gnupg/S.gpg-agent.extra";
              }
            ];
          };
        };
      };
    };
  };
in
[
  ./git
  ./fish
  ./tmux
  ./neovim-ide
  more
]
