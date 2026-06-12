# claude-monitor collector box. Neutral LXC (no client toolchain): runs the
# collector + dashboard as a systemd service, reads the shared token from sops
# via systemd credentials, and opens the dashboard port on the LAN.
{pkgs, ...}: {
  imports = [./../lxc-base.nix];
  networking.hostName = "monitor";

  sops.defaultSopsFile = ../../secrets/monitor.yaml;
  sops.age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];
  sops.secrets.monitor_token = {};

  # LAN-only: 8787 = HTTP machine plane (hosts dial ws://, hooks POST);
  # 8443 = HTTPS for the browser/PWA (Service Workers need a secure context).
  networking.firewall.allowedTCPPorts = [8787 8443];

  systemd.services.claude-monitor = {
    description = "claude-monitor collector + dashboard";
    wantedBy = ["multi-user.target"];
    after = ["network.target"];
    serviceConfig = {
      ExecStart = pkgs.writeShellScript "claude-monitor-start" ''
        export MONITOR_TOKEN="$(cat "$CREDENTIALS_DIRECTORY/monitor_token")"
        # Dual-listener: HTTP :8787 (machines) always; HTTPS :8443 (browser/PWA)
        # with an auto self-signed cert. Cert + VAPID keys persist under the
        # StateDirectory (/var/lib/claude-monitor/tls). Trust the cert once per
        # device to install the PWA + receive Web Push.
        export MONITOR_TLS_ENABLED=1
        export MONITOR_TLS_ADDR=":8443"
        export MONITOR_TLS_IP="10.0.1.123"
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
