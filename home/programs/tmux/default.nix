{
  config,
  pkgs,
  lib,
  ...
}: let
  plugins = pkgs.tmuxPlugins // pkgs.callPackage ./custom-plugins.nix {};
  tmuxConf = builtins.readFile ./default.conf;
  tmux-sessions = pkgs.callPackage ./tmux-sessions.nix {};

  # Absolute store path, NOT $HOME/.nix-profile/bin/fish: that profile path only
  # exists under standalone home-manager (Darwin). On the NixOS containers
  # home-manager runs with `useUserPackages`, so binaries land in
  # /etc/profiles/per-user/<name>/bin and ~/.nix-profile is an empty profile —
  # a dead default-command there kills each pane on spawn and takes the server
  # down with it. The store path is correct on every platform.
  fishBin = "${config.programs.fish.package}/bin/fish";
in {
  programs.tmux = {
    enable = true;
    #agressiveResize = true;
    baseIndex = 1;
    shell = fishBin;
    extraConfig =
      ''
        set -g default-command ${fishBin}
      ''
      + tmuxConf;
    escapeTime = 0;
    keyMode = "vi";
    plugins = with plugins;
      [
        cpu
        nord # theme
        {
          plugin = resurrect;
          extraConfig = "set -g @resurrect-strategy-nvim 'session'";
        }
        {
          plugin = continuum;
          extraConfig = ''
            set -g @continuum-restore 'on'
            set -g @continuum-save-interval '60' # minutes
          '';
        }
      ]
      # Seamless <C-hjkl> between nvim splits and tmux panes — the tmux half of
      # the pair with vimPlugins.vim-tmux-navigator in ../neovim-ide. Replaces the
      # old zellij-nav.nvim + zellij setup.
      #
      # DARWIN ONLY, deliberately: ../neovim-ide (and with it the nvim half) is
      # Darwin-only, and this plugin claims C-hjkl in tmux's ROOT table, forwarding
      # the key into the pane only when that pane matches its `is_vim` check
      # (vim/nvim/view/fzf). On the Linux containers the pane is usually running
      # `claude`, which does NOT match — so shipping it there would swallow C-hjkl
      # (notably C-l) before the Claude Code TUI ever sees it, with no nvim
      # navigation to show for it.
      ++ lib.optionals pkgs.stdenv.isDarwin [vim-tmux-navigator];
    shortcut = "a";
    terminal = "tmux-256color";
  };
  home.packages = [
    tmux-sessions
  ];
}
