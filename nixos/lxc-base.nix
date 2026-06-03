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

  users.users.marcin = {
    isNormalUser = true;
    extraGroups = ["wheel"];
    shell = pkgs.fish;
    openssh.authorizedKeys.keys = [
      # TODO(provisioning): add your Mac's public SSH key here before first rebuild.
    ];
  };
  programs.fish.enable = true;
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
