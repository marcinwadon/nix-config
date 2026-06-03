{
  config,
  lib,
  pkgs,
  modulesPath,
  inputs,
  overlays,
  homeModules,
  profile,
  ...
}: {
  imports = [
    "${modulesPath}/virtualisation/proxmox-lxc.nix"
    inputs.home-manager.nixosModules.home-manager
    inputs.sops-nix.nixosModules.sops
  ];

  # Unprivileged LXC; Proxmox manages container networking.
  # manageHostName = true so each env's networking.hostName takes effect;
  # otherwise the proxmox-lxc module forces hostName to "" (picked from
  # /etc/hostname at runtime), which breaks our per-env hostname config.
  proxmoxLXC = {
    privileged = false;
    manageNetwork = false;
    manageHostName = true;
  };

  networking.useDHCP = lib.mkDefault true;

  nixpkgs = {
    config.allowUnfree = true;
    overlays = overlays;
  };

  time.timeZone = "Europe/Warsaw";
  i18n.defaultLocale = "en_US.UTF-8";

  nix.settings = {
    experimental-features = ["nix-command" "flakes"];
    trusted-users = ["root" "marcin"];
  };

  # Run generic, dynamically-linked binaries (e.g. the native `claude` install
  # in ~/.local/bin) on NixOS via nix-ld's stub loader + a base library set.
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      stdenv.cc.cc.lib # libstdc++ / libgcc_s
      zlib
      openssl
    ];
  };

  users.users.marcin = {
    isNormalUser = true;
    extraGroups = ["wheel"];
    shell = pkgs.fish;
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDuv40fdWOq9h6axo3x4KXJMxvukVFbwUzb+5fvZ2GWKTDjamDOChNx1PF+MfGP30ooxyT+//Ep3vjNDpNbFEqMwCwxb7ehtg76PYtNMc1Ic4xiOfcKiDTl2+ljZxo5IbNgvMc2lZh1mH3uz9lLynRBwLOJjnfVQJmDIqkFgbmxEv30gEZBTEIvSgBup5FnIH23ZSrSEOvNc9+w595SxSI7jCmPafe+U0Uazy4mnA0gVKUjlz3KlXuLfapEyrHhyzqirqgVsk+QRCZUnxHZAxT4mTqGlFRv4HsHoW1nIzq+NV7nnCPQ5HqwbzsrPb0LYwY2oWPzAvn5Fy+ZXmjzUMul327ePcki/c/PoVsvrywSO9t/1ePPs+gb294q5Qu4gUR7fGdpwsFUBWhEdibt/n7OgSau8OGDah/IdhZPuWGmqphOvYrXzb3f4PTJJbpAPKeknsZAWGUaYKNIWnqyeZREDxVyDqrhTBq1xuUlNfFg9AsoU0Jc6w2bjj7pLMIiIZaAmO9kczZaQTFgF6ai3t6OsZ20hvZzrZ4cwRAOWV/Zusv76SiqUwoQdij2awT71ppQPqh9W3RguV+fQgNZuFW0DmqvLs9Ngkg8XjETE1M9fu7O+5dBMuxzDqFB2TWvfE2UkxSXV9PNcqzYwhuCH9/x8V1RjLoRocmN9GwZA9GWCQ=="
    ];
  };
  # mosh: installs mosh-server and opens the UDP port range in the NixOS firewall.
  programs.mosh.enable = true;

  programs.fish = {
    enable = true;
    # Skip NixOS's man-page->completion generation: it crashes on this nixpkgs
    # (`ModuleNotFoundError: deroff`) with the stable-pinned fish. fish's built-in
    # and home-manager completions are unaffected.
    generateCompletions = false;
  };
  security.sudo.wheelNeedsPassword = false;

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };

  # Secrets are provisioned later; don't validate sops files at build time.
  sops.validateSopsFiles = false;

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = {inherit profile;};
    users.marcin = {...}: {
      imports = homeModules ++ [../home/home.nix];
    };
  };

  system.stateVersion = "24.11";
}
