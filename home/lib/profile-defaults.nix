# Default values for the per-environment `profile` specialArg.
# Each profile (home/profiles/<env>.nix) overrides a subset of these.
{
  username = "marcin";

  # Platform marker (externally-provided so it is safe to branch `imports` on it,
  # unlike pkgs.stdenv which derives from config and causes infinite recursion).
  isDarwin = false;

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

  # Build-time GitHub token (Darwin only, from git-crypt secret); null elsewhere.
  # Containers use `gh auth login` interactively instead of a baked token.
  githubToken = null;

  # claude-monitor hook wiring. monitorMachine = null disables the hook entirely
  # (the collector-only "monitor" box and any unconfigured profile). Set it to
  # this machine's label ("mac"/"personal"/"evojam"/"parloa") to install the
  # hook + merge it into ~/.claude/settings.json. monitorUrl points at the
  # collector LXC on the LAN.
  monitorMachine = null;
  monitorUrl = "http://10.0.1.123:8787";
}
