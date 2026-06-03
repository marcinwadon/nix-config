{
  pkgs,
  lib,
  modulesPath,
  ...
}: {
  imports = ["${modulesPath}/virtualisation/proxmox-lxc.nix"];

  proxmoxLXC = {
    privileged = false;
    manageNetwork = false;
  };
  networking.useDHCP = lib.mkForce true;

  nix.settings.experimental-features = ["nix-command" "flakes"];

  users.users.marcin = {
    isNormalUser = true;
    extraGroups = ["wheel"];
  };
  security.sudo.wheelNeedsPassword = false;
  services.openssh.enable = true;

  environment.systemPackages = with pkgs; [git ssh-to-age];

  system.stateVersion = "24.11";
}
