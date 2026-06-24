let
  scripts = {
    config,
    lib,
    pkgs,
    profile ? {},
    ...
  }: let
    defaults = import ../lib/profile-defaults.nix;
    p = lib.recursiveUpdate defaults profile;
  in {
    home.packages =
      lib.optionals p.enableBspCleanup [
        (pkgs.callPackage ./clean-bsp-workspace.nix {})
      ]
      ++ [(pkgs.callPackage ./tmux-close.nix {})]
      ++ lib.optionals p.isDarwin [
        (pkgs.callPackage ./aws-evojam-mfa.nix {})
      ]
      ++ lib.optionals p.enableConstellationScripts [
        (pkgs.callPackage ./h_mainnet.nix {})
        (pkgs.callPackage ./h_testnet.nix {})
        (pkgs.callPackage ./h_integrationnet.nix {})
      ];
  };
in [scripts]
