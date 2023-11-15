{ config, pkgs, lib, ... }:

let
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

  fishConfig = ''
    bind \t accept-autosuggestion
    set fish_greeting
  '' + gpgConfig + fzfConfig + themeConfig;
in
{
  programs.fish = {
    enable = true;
    plugins = [ custom.theme fenv z ];
    interactiveShellInit = ''
      eval (direnv hook fish)
      any-nix-shell fish --info-right | source
    '';
    shellAliases = {
      cat  = "bat";
      dc   = "docker-compose";
      dps  = "docker-compose ps";
      dcd  = "docker-compose down --remove-orphans";
      drm  = "docker images -a -q | xargs docker rmi -f";
      du   = "ncdu --color dark -rr -x";
      ls   = "eza";
      ll   = "ls -a";
      ".." = "cd ..";
      ping = "prettyping";
      tree = "eza -T";
      flush = "dscacheutil -flushcache && killall -HUP mDNSResponder";
      cleanup = "find . -type f -name '*.DS_Store' -ls -delete";
      gpg-restart = "gpg-connect-agent updatestartuptty /bye";
      gpg-reload = "gpg-connect-agent 'scd serialno' 'learn --force' /bye";
    };
    shellInit = fishConfig;
    functions = {
      join = "ssh -o StrictHostKeyChecking=false admin@$argv";
    };
  };

 # xdg.configFile."fish/completions/keytool.fish".text = custom.completions.keytool;
  xdg.configFile."fish/functions/fish_prompt.fish".text = custom.prompt;
}
