{
  config,
  pkgs,
  ...
}: let
  plugins = pkgs.tmuxPlugins // pkgs.callPackage ./custom-plugins.nix {};
  tmuxConf = builtins.readFile ./default.conf;
  tmux-sessions = pkgs.callPackage ./tmux-sessions.nix {};
in {
  programs.tmux = {
    enable = true;
    #agressiveResize = true;
    baseIndex = 1;
    extraConfig = tmuxConf;
    escapeTime = 0;
    keyMode = "vi";
    plugins = with plugins; [
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
    ];
    shortcut = "a";
    terminal = "tmux-256color";
  };
  home.packages = [
    tmux-sessions
  ];
}
