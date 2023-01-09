{ config, lib, pkgs, inputs, ... }:

let

in
{

  imports =
    [
      ./cachix.nix
    ];

  networking = {
    networkmanager = {
      enable = true;
    };

    useDHCP = false;
  };

  i18n.defaultLocale = "en_US.UTF-8";

  time.timeZone = "Europe/Warsaw";

  environment.systemPackages = with pkgs; [
    vim
    wget
  ];

  networking.firewall.enable = false;

  services = {
    openssh = {
      enable = true;
      allowSFTP = true;
      extraConfig = "StreamLocalBindUnlink yes";
    };

    sshd.enable = true;
  };

  programs.fish.enable = true;

  users.users.marcin = {
    isNormalUser = true;
    extraGroups = [ "networkmanager" "wheel" ];
    shell = pkgs.fish;
  };

  users.users.root.openssh.authorizedKeys.keys = [ "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDuv40fdWOq9h6axo3x4KXJMxvukVFbwUzb+5fvZ2GWKTDjamDOChNx1PF+MfGP30ooxyT+//Ep3vjNDpNbFEqMwCwxb7ehtg76PYtNMc1Ic4xiOfcKiDTl2+ljZxo5IbNgvMc2lZh1mH3uz9lLynRBwLOJjnfVQJmDIqkFgbmxEv30gEZBTEIvSgBup5FnIH23ZSrSEOvNc9+w595SxSI7jCmPafe+U0Uazy4mnA0gVKUjlz3KlXuLfapEyrHhyzqirqgVsk+QRCZUnxHZAxT4mTqGlFRv4HsHoW1nIzq+NV7nnCPQ5HqwbzsrPb0LYwY2oWPzAvn5Fy+ZXmjzUMul327ePcki/c/PoVsvrywSO9t/1ePPs+gb294q5Qu4gUR7fGdpwsFUBWhEdibt/n7OgSau8OGDah/IdhZPuWGmqphOvYrXzb3f4PTJJbpAPKeknsZAWGUaYKNIWnqyeZREDxVyDqrhTBq1xuUlNfFg9AsoU0Jc6w2bjj7pLMIiIZaAmO9kczZaQTFgF6ai3t6OsZ20hvZzrZ4cwRAOWV/Zusv76SiqUwoQdij2awT71ppQPqh9W3RguV+fQgNZuFW0DmqvLs9Ngkg8XjETE1M9fu7O+5dBMuxzDqFB2TWvfE2UkxSXV9PNcqzYwhuCH9/x8V1RjLoRocmN9GwZA9GWCQ==" ];
  users.users.marcin.openssh.authorizedKeys.keys = [ "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDuv40fdWOq9h6axo3x4KXJMxvukVFbwUzb+5fvZ2GWKTDjamDOChNx1PF+MfGP30ooxyT+//Ep3vjNDpNbFEqMwCwxb7ehtg76PYtNMc1Ic4xiOfcKiDTl2+ljZxo5IbNgvMc2lZh1mH3uz9lLynRBwLOJjnfVQJmDIqkFgbmxEv30gEZBTEIvSgBup5FnIH23ZSrSEOvNc9+w595SxSI7jCmPafe+U0Uazy4mnA0gVKUjlz3KlXuLfapEyrHhyzqirqgVsk+QRCZUnxHZAxT4mTqGlFRv4HsHoW1nIzq+NV7nnCPQ5HqwbzsrPb0LYwY2oWPzAvn5Fy+ZXmjzUMul327ePcki/c/PoVsvrywSO9t/1ePPs+gb294q5Qu4gUR7fGdpwsFUBWhEdibt/n7OgSau8OGDah/IdhZPuWGmqphOvYrXzb3f4PTJJbpAPKeknsZAWGUaYKNIWnqyeZREDxVyDqrhTBq1xuUlNfFg9AsoU0Jc6w2bjj7pLMIiIZaAmO9kczZaQTFgF6ai3t6OsZ20hvZzrZ4cwRAOWV/Zusv76SiqUwoQdij2awT71ppQPqh9W3RguV+fQgNZuFW0DmqvLs9Ngkg8XjETE1M9fu7O+5dBMuxzDqFB2TWvfE2UkxSXV9PNcqzYwhuCH9/x8V1RjLoRocmN9GwZA9GWCQ==" "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDVO0w7WUdvJKcY7vTE/4/FLG5JFJp43pJaFz4CnwDpJIeJetcdzPrsFVdvsXnRNKRXrGMJN2YKc5BzzsTsdcU+Kg+6YrtdCtygCLgXuwPFcJdKlDBm6u593XKGgohB1WcJmKkraOeqJrqzG7OWm1EUdiyN2fpulSaNN7yVwtDOZAZKaYG5W9x6cNt3lMCO4tI4BiSavQdv+zsk/eHUODBWSZBoBsvtew91VshRPe59kYDcXVuqCMh+THehco3mLHFndaw4L3GxcpfwdUMJwb/lvwEx+Xpg1WPeUsioLBfCAfsIktcSg6D0nyCwvmYcTMumCB1gi2sgz2xIEOWGeoD5Cc2eLIxZkcsHIhMCPtBirtD8EGvlSRGZq/DfVLZ3avT+Ndmuc5rQWVHFW1ITQmRkwMZx9D9E0q0f/cwSGksbm968Soft9QfjuzOa+cTr6vmpAHy5T3Y16BJSIWY1Ytj8R3nNVnMWRHIwRlun9zy6LQvD5n+B5X6UE61gELgLj3kUhRUvRqLtj84WYpADU2oiG7IzzMjZlg2sGzpuzt1wpOKJnx+I/02nKnwOa+2wm3zztJX90klKLtO+6jBwUjwj5h1wd4IwhHQPBLHjFF05rnbmgCCQ+e1Izy3/evmujIs1abcrI7yjxjhAsLmVnzlFbD1yTR0eDbbsiuZU2PAeOw==" ];

  nixpkgs.config.allowUnfree = true;

  nix = {
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 7d";
    };

    package = pkgs.nixVersions.stable;
    registry.nixpkgs.flake = inputs.nixpkgs;

    settings = {
      auto-optimise-store = true;

      trusted-users = [ "root" "marcin" ];

      experimental-features = [ "nix-command" "flakes" ];

      keep-outputs = true;
      keep-derivations = true;
    };
  };

  system.stateVersion = "23.05";
}
