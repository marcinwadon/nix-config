{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  environment.systemPackages = with pkgs; [
    vim
    wget
    fish
    yubikey-manager
    yubikey-personalization
    gnupg
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
    };

    extraOptions = ''
      keep-outputs = true
      keep-derivations = true
    '';
  };

  ids.gids.nixbld = 350;

  system.stateVersion = 4;
}
