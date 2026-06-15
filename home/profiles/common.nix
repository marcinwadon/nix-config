# Shared Linux profile base. Per-env profiles import & extend this.
{
  username = "marcin";
  enableConstellationScripts = false;
  enableBspCleanup = false;

  # Share the Claude Code config (skills/commands/agents/CLAUDE.md + writable
  # memory-rule stubs) on the Linux coding CTs. Darwin + the monitor box do not
  # import this base, so they stay opted out.
  shareClaudeConfig = true;

  # Authenticate to GitHub with the per-env signing key (no ssh-agent in the
  # container — point IdentityFile straight at the sops-provisioned private key).
  sshMatchBlocks = {
    "github.com" = {
      identityFile = "/run/secrets/ssh_signing_key";
      identitiesOnly = true;
    };
  };

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
