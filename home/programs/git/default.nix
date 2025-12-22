{
  config,
  pkgs,
  ...
}: let
  parloaSecrets = import ../../secrets/parloa.nix;

  gitConfig = {
    core = {
      editor = "nvim";
      pager = "diff-so-fancy | less --tabs=4 -RFX";
    };
    init.defaultBranch = "main";
    merge = {
      conflictStyle = "diff3";
      tool = "vim_mergetool";
    };
    mergetool."vim_mergetool" = {
      cmd = "nvim -f -c \"MergetoolStart\" \"$MERGED\" \"$BASE\" \"$LOCAL\" \"$REMOTE\"";
      prompt = false;
    };
    pull.rebase = false;
    push.autoSetupRemote = true;
    url = {
      "https://github.com/".insteadOf = "gh:";
      "ssh://git@github.com".pushInsteadOf = "gh:";
    };
  };

  rg = "${pkgs.ripgrep}/bin/rg";
in {
  home.packages = with pkgs; [
    diff-so-fancy
    git-crypt
    hub
    tig
  ];

  # Copy Parloa-specific Git config to the right location
  home.file.".config/git/parloa.gitconfig".text = parloaSecrets.gitConfig;

  programs.git = {
    enable = true;
    settings = gitConfig // {
      alias = {
        amend = "commit --amend -m";
        fixup = "!f(){ git reset --soft HEAD~\${1} && git commit --amend -C HEAD; };f";
        loc = "!f(){ git ls-files | ${rg} \"\\.\${1}\" | xargs wc -l; };f";
        br = "branch";
        co = "checkout";
        st = "status";
        ls = "log --pretty=format:\"%C(yellow)%h%Cred%d\\\\ %Creset%s%Cblue\\\\ [%cn]\" --decorate";
        ll = "log --pretty=format:\"%C(yellow)%h%Cred%d\\\\ %Creset%s%Cblue\\\\ [%cn]\" --decorate --numstat";
        cm = "commit -m";
        ca = "commit -am";
        dc = "diff --cached";
        lg = "log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit --date=relative";
        amm = "commit --amend";
        mr = "merge --ff-only";
      };
      user = {
        email = "mwadon@evojam.com";
        name = "Marcin Wadon";
      };
      commit.gpgsign = true;
      user.signingkey = "23E5A318AE8D2861";
    };
    includes = [
      {
        condition = "gitdir:${parloaSecrets.projectPath}";
        path = "~/.config/git/parloa.gitconfig";
      }
    ];
    ignores = [
      "*.bloop"
      "*.bsp"
      "*.metals"
      "*.metals.sbt"
      "*metals.sbt"
      "*.direnv"
      "*.envrc"
      "*hie.yaml"
      "*.mill-version"
      "*.jvmopts"
      ".DS_Store"
    ];
  };
}
