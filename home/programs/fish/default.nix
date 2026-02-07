{
  config,
  pkgs,
  lib,
  ...
}: let
  fzfConfig = ''
    set -x FZF_DEFAULT_OPTS "--preview='bat {} --color=always'" \n
    set -x SKIM_DEFAULT_COMMAND "rg --files || fd || find ."
  '';

  themeConfig = ''
    set -g theme_display_date no
    set -g theme_display_git_master_branch no
    set -g theme_nerd_fonts yes
    set -g theme_newline_cursor yes
    set -g theme_color_scheme solarized
  '';

  gpgConfig = ''
    set -x GPG_TTY (tty)
    set -x SSH_AUTH_SOCK (gpgconf --list-dirs agent-ssh-socket)
    gpgconf --launch gpg-agent
    gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1
  '';

  githubConfig = ''
    set -x GITHUB_TOKEN ${import ../../secrets/github}
  '';

  custom = pkgs.callPackage ./plugins.nix {};

  fenv = {
    name = "foreign-env";
    src = pkgs.fishPlugins.foreign-env.src;
  };

  z = {
    name = "z";
    src = pkgs.fetchFromGitHub {
      owner = "jethrokuan";
      repo = "z";
      rev = "master";
      sha256 = "sha256-+FUBM7CodtZrYKqU542fQD+ZDGrd2438trKM0tIESs0=";
    };
  };

  fishConfig =
    ''
      bind \t accept-autosuggestion
      set fish_greeting
    ''
    + gpgConfig
    + fzfConfig
    + themeConfig
    + githubConfig;
in {
  programs.fish = {
    enable = true;
    plugins = [custom.theme fenv z];
    interactiveShellInit = ''
      eval (direnv hook fish)
      any-nix-shell fish --info-right | source
    '';
    shellAliases = {
      cat = "bat";
      dc = "docker-compose";
      dps = "docker-compose ps";
      dcd = "docker-compose down --remove-orphans";
      drm = "docker images -a -q | xargs docker rmi -f";
      du = "ncdu --color dark -rr -x";
      ls = "eza";
      ll = "ls -a";
      ns = "nix-search";
      ".." = "cd ..";
      ping = "prettyping";
      tree = "eza -T";
      flush = "dscacheutil -flushcache && killall -HUP mDNSResponder";
      cleanup = "find . -type f -name '*.DS_Store' -ls -delete";
      gpg-restart = "gpg-connect-agent updatestartuptty /bye";
      gpg-reload = "gpg-connect-agent 'scd serialno' 'learn --force' /bye";
      claudey = "claude --dangerously-skip-permissions";
    };
    shellInit = fishConfig;
    functions = {
      join = "ssh -o StrictHostKeyChecking=false admin@$argv";

      # Aikido safe-chain command wrapper
      wrapSafeChainCommand = ''
        set -l original_cmd $argv[1]
        set -l aikido_cmd $argv[2]
        set -l cmd_args $argv[3..-1]

        if command -v $aikido_cmd > /dev/null 2>&1
          command $aikido_cmd $cmd_args
        else
          echo "⚠️  Aikido safe-chain not found for $original_cmd"
          command $original_cmd $cmd_args
        end
      '';

      # Aikido safe-chain wrappers
      pnpm = ''
        if test "$argv[1]" = "-v" -o "$argv[1]" = "--version"
          command pnpm $argv
          return
        end
        wrapSafeChainCommand "pnpm" "aikido-pnpm" $argv
      '';

      npm = ''
        if test "$argv[1]" = "-v" -o "$argv[1]" = "--version"
          command npm $argv
          return
        end
        wrapSafeChainCommand "npm" "aikido-npm" $argv
      '';
    };
  };

  # xdg.configFile."fish/completions/keytool.fish".text = custom.completions.keytool;
  xdg.configFile."fish/functions/fish_prompt.fish".text = custom.prompt;
}
