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
        #startAgent = false;
        matchBlocks = import ../secrets/ssh.nix;
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
