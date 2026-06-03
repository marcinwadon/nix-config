# Shared Linux profile base. Per-env profiles import & extend this.
{
  username = "marcin";
  enableConstellationScripts = false;
  enableBspCleanup = false;
  sshMatchBlocks = {};

  git = {
    userName = "Marcin Wadon";
    signing = {
      enable = true;
      format = "ssh";
      key = "/run/secrets/ssh_signing_key.pub";
      signByDefault = true;
      allowedSignersFile = "/run/secrets/allowed_signers";
    };
  };

  githubTokenFile = "/run/secrets/github_token";
}
