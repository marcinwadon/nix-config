# Darwin profile — reproduces the pre-refactor macOS configuration exactly.
let
  parloaSecrets = import ../secrets/parloa.nix;
in {
  username = "marcinwadon";

  githubToken = import ../secrets/github;

  enableConstellationScripts = true;
  enableBspCleanup = true;

  git = {
    userName = "Marcin Wadon";
    userEmail = "mwadon@evojam.com";
    signing = {
      enable = true;
      format = "openpgp";
      key = "23E5A318AE8D2861";
      signByDefault = true;
      allowedSignersFile = null;
    };
    includes = [
      {
        condition = "gitdir:${parloaSecrets.projectPath}";
        path = "~/.config/git/parloa.gitconfig";
      }
    ];
    extraGitconfigFiles = {
      "parloa.gitconfig" = parloaSecrets.gitConfig;
    };
  };
}
