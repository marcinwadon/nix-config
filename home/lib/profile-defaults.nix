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

  # Symlink the shared Claude Code config (CLAUDE.md routing file + skills +
  # commands + agents) into ~/.claude, and seed writable memory-rule stubs so
  # the per-machine auto-update memory rule has structure to grow into. Enabled
  # on the Linux coding CTs; left off on Darwin (the Mac keeps its own live,
  # writable ~/.claude as the author) and on the collector-only monitor box.
  shareClaudeConfig = false;

  # SSH client config (home-manager programs.ssh.matchBlocks).
  sshMatchBlocks = {};

  # Build-time GitHub token (Darwin only, from git-crypt secret); null elsewhere.
  # Containers use `gh auth login` interactively instead of a baked token.
  githubToken = null;

  # claude-monitor hook wiring. monitorMachine = null disables the hook entirely
  # (the collector-only "monitor" box and any unconfigured profile). Set it to
  # this machine's label ("mac"/"personal"/"evojam"/"parloa"/"m1-personal"/
  # "m1-evojam"/"m1-parloa") to install the hook + merge it into
  # ~/.claude/settings.json. monitorUrl points at the collector LXC on the LAN.
  monitorMachine = null;
  monitorUrl = "http://10.0.1.123:8787";

  # Absolute path the hook/tailer/host wrappers read MONITOR_TOKEN from at
  # runtime. null = derive the platform default (sops on NixOS, ~/.config on
  # darwin). Set it explicitly on a Linux box that has no sops-nix — otherwise
  # the token file is unreadable, MONITOR_TOKEN stays unset, and the host
  # silently never registers with the collector.
  monitorTokenFile = null;

  # Same idea for the memory MCP token, which is a DIFFERENT secret: the
  # collector resolves it to a machine label so a session's memory scope is
  # DERIVED rather than claimed by the caller. null takes the platform default
  # (/run/secrets/memory_mcp_token on Linux, ~/.config/claude-monitor/mcp-token
  # on darwin); the M1 overrides it because that box has no sops-nix. Unlike
  # MONITOR_TOKEN this one is read at ACTIVATION time, not runtime, because
  # Claude Code wants the URL (token included) sitting in ~/.claude.json — so it
  # lands in a 0600 file in $HOME, never in the Nix store.
  memoryMcpTokenFile = null;
}
