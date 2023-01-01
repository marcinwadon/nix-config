{ config, pkgs, ... }:

{
  imports = [ <nixpkgs/nixos/modules/virtualisation/lxc-container.nix> ];
  
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  systemd.suppressedSystemUnits = [
    "dev-mqueue.mount"
    "sys-kernel-debug.mount"
    "sys-fs-fuse-connections.mount"
  ];

  networking.networkmanager.enable = true;
  networking.interfaces.eth0.ipv4.addresses = [ {
    address = "10.0.1.170";
    prefixLength = 24;
  } ];
  networking.defaultGateway = "10.0.1.1";
  networking.nameservers = [ "10.0.1.1" ];
  networking.hostName = "nixos";

  services.openssh = {
    enable = true;
  };

  users.users.root.openssh.authorizedKeys.keys = [ "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDuv40fdWOq9h6axo3x4KXJMxvukVFbwUzb+5fvZ2GWKTDjamDOChNx1PF+MfGP30ooxyT+//Ep3vjNDpNbFEqMwCwxb7ehtg76PYtNMc1Ic4xiOfcKiDTl2+ljZxo5IbNgvMc2lZh1mH3uz9lLynRBwLOJjnfVQJmDIqkFgbmxEv30gEZBTEIvSgBup5FnIH23ZSrSEOvNc9+w595SxSI7jCmPafe+U0Uazy4mnA0gVKUjlz3KlXuLfapEyrHhyzqirqgVsk+QRCZUnxHZAxT4mTqGlFRv4HsHoW1nIzq+NV7nnCPQ5HqwbzsrPb0LYwY2oWPzAvn5Fy+ZXmjzUMul327ePcki/c/PoVsvrywSO9t/1ePPs+gb294q5Qu4gUR7fGdpwsFUBWhEdibt/n7OgSau8OGDah/IdhZPuWGmqphOvYrXzb3f4PTJJbpAPKeknsZAWGUaYKNIWnqyeZREDxVyDqrhTBq1xuUlNfFg9AsoU0Jc6w2bjj7pLMIiIZaAmO9kczZaQTFgF6ai3t6OsZ20hvZzrZ4cwRAOWV/Zusv76SiqUwoQdij2awT71ppQPqh9W3RguV+fQgNZuFW0DmqvLs9Ngkg8XjETE1M9fu7O+5dBMuxzDqFB2TWvfE2UkxSXV9PNcqzYwhuCH9/x8V1RjLoRocmN9GwZA9GWCQ==" ];  


  environment.systemPackages = with pkgs; [ vim ];
}
