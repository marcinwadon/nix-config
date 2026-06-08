{
  imports = [./../lxc-base.nix];
  networking.hostName = "parloa";

  sops.defaultSopsFile = ../../secrets/parloa.yaml;
  sops.age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];
  sops.secrets.ssh_signing_key = {owner = "marcin";};
  sops.secrets.allowed_signers = {owner = "marcin";};
  # Shared claude-monitor token; the (marcin-run) hook wrapper reads it at runtime.
  sops.secrets.monitor_token = {owner = "marcin";};
}
