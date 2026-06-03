{
  config,
  pkgs,
  lib,
  profile ? {},
  ...
}: let
  defaults = import ../../lib/profile-defaults.nix;
  p = lib.recursiveUpdate defaults profile;
  g = p.git;

  rg = "${pkgs.ripgrep}/bin/rg";

  baseConfig = {
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

  # NOTE: `//` is a shallow merge. Build each nested attr (`user`, `gpg`) in ONE
  # place so sub-keys aren't clobbered. `gpg.format` is emitted only for ssh —
  # openpgp is git's default, so omitting it keeps the Darwin config byte-identical.
  identityConfig = let
    s = g.signing;
    emitFormat = s.enable && s.format == "ssh";
  in
    {
      user =
        {
          email = g.userEmail;
          name = g.userName;
        }
        // lib.optionalAttrs (s.enable && s.key != null) {
          signingkey = s.key;
        };
    }
    // lib.optionalAttrs s.enable {
      commit.gpgsign = s.signByDefault;
    }
    // lib.optionalAttrs emitFormat {
      gpg =
        {format = "ssh";}
        // lib.optionalAttrs (s.allowedSignersFile != null) {
          ssh.allowedSignersFile = s.allowedSignersFile;
        };
    };

  aliases = {
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
in {
  home.packages = with pkgs; [
    diff-so-fancy
    git-crypt
    hub
    tig
  ];

  # Extra gitconfig files written under ~/.config/git/ (e.g. Parloa's).
  home.file =
    lib.mapAttrs'
    (name: text: lib.nameValuePair ".config/git/${name}" {inherit text;})
    g.extraGitconfigFiles;

  programs.git = {
    enable = true;
    settings = baseConfig // identityConfig // {alias = aliases;};
    includes = g.includes;
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
