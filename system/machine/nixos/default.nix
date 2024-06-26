{
  config,
  pkgs,
  ...
}: {
  imports = [
    <nixpkgs/nixos/modules/virtualisation/lxc-container.nix>
    ./hardware-configuration.nix
  ];

  systemd.suppressedSystemUnits = [
    "dev-mqueue.mount"
    "sys-kernel-debug.mount"
    "sys-fs-fuse-connections.mount"
  ];

  networking = {
    hostName = "nixos";
    interfaces.eth0.ipv4.addresses = [
      {
        address = "10.0.1.170";
        prefixLength = 24;
      }
    ];

    defaultGateway = "10.0.1.1";
    nameservers = ["10.0.1.1"];
  };
}
