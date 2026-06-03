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
      # Private key path — git/ssh-keygen signs directly with it (headless, no agent).
      key = "/run/secrets/ssh_signing_key";
      signByDefault = true;
      allowedSignersFile = "/run/secrets/allowed_signers";
    };
  };
}
