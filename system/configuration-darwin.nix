{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  environment.systemPackages = [
    pkgs.vim
    pkgs.wget
    pkgs.fish
    # kitty lives here, not in home.packages: nix-darwin aliases GUI bundles into
    # /Applications/Nix Apps AND puts `kitty`/`kitten` on PATH from the same
    # derivation, so the app and the kittens can't drift out of version sync.
    # Its config is Home Manager's (home/programs/kitty).
    pkgs.kitty
    # Same reasoning as kitty: a GUI bundle here gets aliased into
    # /Applications/Nix Apps by nix-darwin. Not in nixpkgs — see ./pkgs.
    (pkgs.callPackage ./pkgs/ghosthub.nix {})
    pkgs.yubikey-manager
    pkgs.yubikey-personalization
    pkgs.gnupg
  ];

  programs.fish.enable = true;

  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  system.activationScripts.postActivation.text = ''
    sudo chsh -s ${lib.getBin pkgs.fish}/bin/fish marcinwadon
  '';

  nixpkgs.config.allowUnfree = true;

  # Set primary user for system defaults
  system.primaryUser = "marcinwadon";

  system.defaults = {
    dock = {
      autohide = true;
      showhidden = true;
      mru-spaces = false;
      minimize-to-application = true;
      show-recents = false;
    };
    finder = {
      AppleShowAllExtensions = true;
      QuitMenuItem = true;
      FXEnableExtensionChangeWarning = true;
      ShowPathbar = true;
      ShowStatusBar = true;
    };
    NSGlobalDomain = {
      AppleShowScrollBars = "Always";
      InitialKeyRepeat = 14;
      KeyRepeat = 1;
    };

    # Ghosthub bundles Sparkle and ships with auto-update on, but it lives in
    # the read-only nix store and cannot replace itself. Turn the updater off
    # so it doesn't nag with failures; version bumps happen in ./pkgs/ghosthub.nix.
    CustomUserPreferences."com.ghosthub" = {
      SUEnableAutomaticChecks = false;
      SUAutomaticallyUpdate = false;
      # Sparkle's first-run "check for updates automatically?" prompt would
      # overwrite the above; pretend we've already answered it.
      SUHasLaunchedBefore = true;
    };
  };

  nix = {
    gc = {
      automatic = true;
      interval = {
        Hour = 3;
        Minute = 15;
      };
      options = "--delete-older-than 7d";
    };

    registry.nixpkgs.flake = inputs.nixpkgs;

    optimise.automatic = true;

    settings = {
      experimental-features = ["nix-command" "flakes"];
      warn-dirty = false;
      trusted-users = ["root" "marcinwadon"];
      substituters = ["https://claude-code.cachix.org"];
      trusted-public-keys = ["claude-code.cachix.org-1:YeXf2aNu7UTX8Vwrze0za1WEDS+4DuI2kVeWEE4fsRk="];
      keep-outputs = true;
      keep-derivations = true;
    };
  };

  ids.gids.nixbld = 350;

  system.stateVersion = 4;
}
