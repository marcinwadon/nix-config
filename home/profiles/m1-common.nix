# Shared base for the three Mac mini M1 users (Fedora Asahi Remix, no NixOS).
#
# A function of the identity so every per-user path is derived once. Called by
# home/profiles/m1-<client>.nix.
#
# CRITICAL: common.nix — the shared Linux base — hardcodes three absolute
# /run/secrets/* paths that DO NOT EXIST on this box, because there is no
# sops-nix here. All three are overridden below. Missing them fails silently:
# a wrong identityFile surfaces only at the first `git push`, and a wrong
# signing key only at the first commit.
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

    # No sops on this box; the token is a plain 0600 file placed at bootstrap.
    monitorTokenFile = "${home}/.config/claude-monitor/token";

    # Override 1 of 3. Also the GitHub auth identity, not just signing.
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
        # Overrides 2 and 3.
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
