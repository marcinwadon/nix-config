# claude-monitor collector box. Neutral LXC (no client toolchain): runs the
# collector + dashboard as a systemd service, reads the shared token from sops
# via systemd credentials, and opens the dashboard port on the LAN.
{pkgs, ...}: {
  imports = [./../lxc-base.nix];
  networking.hostName = "monitor";

  sops.defaultSopsFile = ../../secrets/monitor.yaml;
  sops.age.sshKeyPaths = ["/etc/ssh/ssh_host_ed25519_key"];
  sops.secrets.monitor_token = {};
  # Orchestrator secrets (added to secrets/monitor.yaml via sops; see RUNBOOK).
  # Kept in sops rather than plaintext .nix because this repo is public:
  # the bot token + LLM key are true secrets, and the chat id + LiteLLM URL
  # are personal/internal and should not be committed in the clear.
  sops.secrets.telegram_bot_token = {};
  sops.secrets.telegram_chat_id = {};
  sops.secrets.llm_api_key = {};
  sops.secrets.llm_base_url = {};

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

  # Orchestrator: a headless sidecar that watches the collector's /stream SSE,
  # triages blocked sessions through an LLM + policy (via the operator's LiteLLM
  # gateway), and relays to Telegram with a live board. It is a plain dashboard
  # client over localhost:8787 — no new collector endpoints, no token needed.
  systemd.services.claude-monitor-orchestrator = {
    description = "claude-monitor Telegram session orchestrator";
    wantedBy = ["multi-user.target"];
    # Start after the collector so /stream is up (best-effort; the watcher
    # reconnects with backoff regardless).
    after = ["network.target" "claude-monitor.service"];
    wants = ["claude-monitor.service"];
    serviceConfig = {
      ExecStart = pkgs.writeShellScript "claude-monitor-orchestrator-start" ''
        export TELEGRAM_BOT_TOKEN="$(cat "$CREDENTIALS_DIRECTORY/telegram_bot_token")"
        export TELEGRAM_CHAT_ID="$(cat "$CREDENTIALS_DIRECTORY/telegram_chat_id")"
        export LLM_API_KEY="$(cat "$CREDENTIALS_DIRECTORY/llm_api_key")"
        export LLM_BASE_URL="$(cat "$CREDENTIALS_DIRECTORY/llm_base_url")"
        # Non-secret config (safe in the public repo).
        export LLM_MODEL="claude-sonnet-4-6"
        export COLLECTOR_BASE_URL="http://localhost:8787"
        # Policy file is optional: a missing path falls back to the built-in
        # aggressive default. Drop a policy.md here to override.
        export POLICY_PATH="/var/lib/claude-monitor-orchestrator/policy.md"
        export ORCHESTRATOR_DB="/var/lib/claude-monitor-orchestrator/orchestrator.db"
        exec ${pkgs.claude-monitor}/bin/claude-monitor-orchestrator
      '';
      LoadCredential = [
        "telegram_bot_token:/run/secrets/telegram_bot_token"
        "telegram_chat_id:/run/secrets/telegram_chat_id"
        "llm_api_key:/run/secrets/llm_api_key"
        "llm_base_url:/run/secrets/llm_base_url"
      ];
      DynamicUser = true;
      StateDirectory = "claude-monitor-orchestrator"; # /var/lib/... (db + optional policy.md)
      Restart = "on-failure";
      RestartSec = 5;
    };
  };
}
