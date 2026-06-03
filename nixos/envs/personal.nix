{
  imports = [./../lxc-base.nix];
  networking.hostName = "personal";

  sops.defaultSopsFile = ../../secrets/personal.yaml;
  sops.age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];
  sops.secrets.ssh_signing_key = {owner = "marcin";};
  sops.secrets.allowed_signers = {owner = "marcin";};
}
