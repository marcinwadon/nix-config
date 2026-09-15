{
  imports = [./../lxc-base.nix];
  networking.hostName = "evojam";

  sops.defaultSopsFile = ../../secrets/evojam.yaml;
  sops.age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];
  sops.secrets.ssh_signing_key = {owner = "marcin";};
  sops.secrets.allowed_signers = {owner = "marcin";};
  # Shared claude-monitor token; the (marcin-run) hook wrapper reads it at runtime.
  sops.secrets.monitor_token = {owner = "marcin";};
  # Per-machine memory MCP token. Separate from monitor_token: the collector
  # maps it to this machine's label, which is how a session's memory scope is
  # derived instead of claimed. Read at home-manager activation time to register
  # the MCP server in ~/.claude.json.
  sops.secrets.memory_mcp_token = {owner = "marcin";};
}
