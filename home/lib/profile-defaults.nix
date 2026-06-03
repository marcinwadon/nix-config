# Default values for the per-environment `profile` specialArg.
# Each profile (home/profiles/<env>.nix) overrides a subset of these.
{
  username = "marcin";

  # Git identity + signing for this environment.
  git = {
    userName = "Marcin Wadon";
    userEmail = "marcin@example.invalid"; # always overridden by a profile
    signing = {
      enable = false;
      format = "ssh"; # "ssh" | "openpgp"
      key = null; # signing key (ssh pubkey path, or gpg key id)
      signByDefault = false;
      allowedSignersFile = null; # ssh signing: path to allowed_signers
    };
    includes = []; # list of { condition; path; } for gitdir includes
    extraGitconfigFiles = {}; # name -> text, written under ~/.config/git/
  };

  # Extra packages for this env, as a function of pkgs (kept minimal).
  extraPackages = _pkgs: [];

  # Toggles for project-specific bits.
  enableConstellationScripts = false; # h_mainnet/h_testnet/h_integrationnet
  enableBspCleanup = false; # clean-bsp-workspace

  # SSH client config (home-manager programs.ssh.matchBlocks).
  sshMatchBlocks = {};

  # Runtime path to a GitHub token file (sops-provisioned on Linux); null on Darwin.
  githubTokenFile = null;

  # Build-time GitHub token (Darwin only, from git-crypt secret); null elsewhere.
  githubToken = null;
}
