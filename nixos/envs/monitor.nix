# claude-monitor collector box. Neutral LXC (no client toolchain): runs the
# collector + dashboard as a systemd service, reads the shared token from sops
# via systemd credentials, and opens the dashboard port on the LAN.
{pkgs, ...}: {
  imports = [./../lxc-base.nix];
  networking.hostName = "monitor";

  sops.defaultSopsFile = ../../secrets/monitor.yaml;
  sops.age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];
  sops.secrets.monitor_token = {};

  # LAN-only dashboard + ingest port.
  networking.firewall.allowedTCPPorts = [8787];

  systemd.services.claude-monitor = {
    description = "claude-monitor collector + dashboard";
    wantedBy = ["multi-user.target"];
    after = ["network.target"];
    serviceConfig = {
      ExecStart = pkgs.writeShellScript "claude-monitor-start" ''
        export MONITOR_TOKEN="$(cat "$CREDENTIALS_DIRECTORY/monitor_token")"
        exec ${pkgs.claude-monitor}/bin/claude-monitor -addr :8787 -db /var/lib/claude-monitor/cm.db
      '';
      # systemd reads the sops secret as root and exposes it to the (dynamic)
      # service user under $CREDENTIALS_DIRECTORY — no world-readable copy.
      LoadCredential = ["monitor_token:/run/secrets/monitor_token"];
      DynamicUser = true;
      StateDirectory = "claude-monitor"; # /var/lib/claude-monitor (db lives here)
      Restart = "on-failure";
      RestartSec = 2;
    };
  };
}
