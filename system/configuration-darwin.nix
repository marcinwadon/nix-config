{ config, lib, pkgs, inputs, ... }:

let

in
{
  environment.systemPackages = with pkgs; [
    vim wget fish yubikey-manager yubikey-personalization gnupg
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

  services.nix-daemon.enable = true;

  system.defaults = {
    dock = {
      autohide = true;
      showhidden = true;
      mru-spaces = false;
    };
    finder = {
      AppleShowAllExtensions = true;
      QuitMenuItem = true;
      FXEnableExtensionChangeWarning = true;
    };
  };

  nix = {
    gc = {
      automatic = true;
      interval = { Hour = 3; Minute = 15; };
      options = "--delete-older-than 7d";
    };

    registry.nixpkgs.flake = inputs.nixpkgs;

    extraOptions = ''
      keep-outputs = true
      keep-derivations = true
      experimental-features = nix-command flakes
    '';

    settings = {
      auto-optimise-store = true;
    };
  };

  system.stateVersion = 4;
}
