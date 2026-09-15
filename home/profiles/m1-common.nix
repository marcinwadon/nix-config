# Shared base for the three Mac mini M1 users (Fedora Asahi Remix, no NixOS).
#
# A function of the identity so every per-user path is derived once. Called by
# home/profiles/m1-<client>.nix.
#
# CRITICAL: there are FIVE reachable /run/secrets/* paths that DO NOT EXIST on
# this box, because there is no sops-nix here — all five are overridden below.
# Missing one fails silently: a wrong identityFile surfaces only at the first
# `git push`, a wrong signing key only at the first commit, a wrong monitor
# token only at the first hook run, and a wrong MCP token only as a session
# that quietly has no memory tools.
#   1. ../programs/claude-monitor-hook/default.nix  the tokenFile fallback
#      used whenever monitorTokenFile is null — not a common.nix field, but
#      still a live /run/secrets default this profile must not inherit.
#   2. ../programs/claude-monitor-hook/default.nix  the mcpTokenFile fallback,
#      the same trap for the separate memory MCP token.
#   3. common.nix:16  sshMatchBlocks."github.com".identityFile
#   4. common.nix:27  git.signing.key
#   5. common.nix:29  git.signing.allowedSignersFile
# Numbered to match the "Override N of 5" tripwire comments below, in the
# order they appear in the code.
# checks.${system}.no-m1-secret-leak (flake.nix) reads exactly TWO rendered
# fields: home.file.".ssh/config".text and programs.git.settings — so it is
# the permanent regression guard for overrides 2-4 only (sshMatchBlocks and
# git.signing land in those two fields). Overrides 1 and 2 (monitorTokenFile,
# memoryMcpTokenFile) render only into the hook/tailer/host wrapper's SCRIPT
# TEXT and an activation script — which reach the module system solely as store
# paths, so neither field the check scans can see them. Those two are guarded
# only by live verification (the host/tailer must come up `active`, and
# `claude mcp list` must show the memory server), not by this check.
{
  client,
  email,
}: let
  common = import ./common.nix;
  username = "marcin-${client}";
  home = "/home/${username}";
  signingKey = "${home}/.ssh/id_ed25519_signing";
  allowedSigners = "${home}/.config/git/allowed_signers";
in
  common
  // {
    inherit username;

    # Dashboard label. Fleet-unique: the collector keys host connections by
    # machine name and closes the previous one, so reusing a CT's label would
    # make the two evict each other in a loop.
    monitorMachine = "m1-${client}";

    # Override 1 of 5. No sops on this box, so this replaces the
    # /run/secrets/monitor_token fallback the hook module (default.nix:32)
    # would otherwise pick for a Linux machine; the token is a plain 0600
    # file placed at bootstrap.
    monitorTokenFile = "${home}/.config/claude-monitor/token";

    # Override 2 of 5. Same reason as override 1, different secret: the memory
    # MCP token, which the collector maps to this machine's label so a session's
    # memory scope is derived rather than claimed. Also a plain 0600 file placed
    # at bootstrap. Left unset, the hook module would point at
    # /run/secrets/memory_mcp_token and every session here would silently come
    # up with no memory tools.
    memoryMcpTokenFile = "${home}/.config/claude-monitor/mcp-token";

    # Override 3 of 5. Also the GitHub auth identity, not just signing.
    #
    # Deliberately a WHOLESALE replacement (not a merge with common.git):
    # this file names the only match block this box needs (github.com), so a
    # full replace fails in the SAFE direction — a future block added to
    # common.nix's sshMatchBlocks would silently never reach here (a dropped
    # feature, not a leak) rather than silently arriving unreviewed. If
    # common.nix ever needs another host block on the M1s, add it here by
    # hand, on purpose.
    sshMatchBlocks = {
      "github.com" = {
        identityFile = signingKey;
        identitiesOnly = true;
      };
    };

    git =
      common.git
      // {
        userEmail = email;
        # Overrides 4 and 5 of 5.
        #
        # Deliberately a KEY-WISE merge (not a wholesale replace of
        # common.git.signing): `enable`/`format`/`signByDefault` are not
        # secrets, and inheriting them lets this box track future
        # non-secret signing changes in common.nix without edits here. The
        # trade-off is the failure direction this file exists to avoid: a
        # future secret-bearing field added anywhere under common.nix's
        # `git` (or a new top-level attr outside sshMatchBlocks) would
        # arrive unguarded, silently. checks.${system}.no-m1-secret-leak in
        # flake.nix is the regression net for exactly that drift — it scans
        # the RENDERED config, not this override list, so it still catches a
        # leak this comment fails to anticipate.
        signing =
          common.git.signing
          // {
            key = signingKey;
            allowedSignersFile = allowedSigners;
          };
        # Delivers the repo's plaintext allowed_signers to the path above.
        extraGitconfigFiles = {
          "allowed_signers" = builtins.readFile ./allowed_signers;
        };
      };
  }
