{
  imports = [./../lxc-base.nix];
  networking.hostName = "evojam";

  sops.defaultSopsFile = ../../secrets/evojam.yaml;
  sops.age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];
  sops.secrets.github_token = {owner = "marcin";};
  sops.secrets."ssh_signing_key" = {owner = "marcin";};
  sops.secrets."ssh_signing_key.pub" = {owner = "marcin";};
  sops.secrets."allowed_signers" = {owner = "marcin";};
}
