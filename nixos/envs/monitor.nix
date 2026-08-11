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
  # the bot/app tokens + LLM key are true secrets, and the channel id + LiteLLM
  # URL are personal/internal and should not be committed in the clear.
  # Slack surface (SP1): the orchestrator moved from Telegram to a Slack Socket
  # Mode app — bot token (xoxb), app-level token (xapp, connections:write), and
  # the hub channel id.
  sops.secrets.slack_bot_token = {};
  sops.secrets.slack_app_token = {};
  sops.secrets.slack_channel_id = {};
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
        # Session auto-naming: title unnamed sessions from their first prompts via
        # the operator's LiteLLM gateway — the SAME key/URL the orchestrator uses
        # (reuses the existing llm_api_key/llm_base_url sops secrets). Unset → the
        # collector silently skips auto-naming.
        export LLM_API_KEY="$(cat "$CREDENTIALS_DIRECTORY/llm_api_key")"
        export LLM_BASE_URL="$(cat "$CREDENTIALS_DIRECTORY/llm_base_url")"
        export LLM_MODEL="claude-sonnet-4-6"
        # Project picker: the directories each host offers when starting a
        # session. Absolute paths on the TARGET machine (the host expands a
        # leading ~ itself); a root that does not exist there is skipped, and
        # browse is additionally fenced to the host's home directory. Unset →
        # the picker falls back to paths derived from session history.
        export WORKSPACE_ROOTS="mac=/Users/marcinwadon/Projects/parloa,/Users/marcinwadon/Projects/marcinwadon,/Users/marcinwadon/Projects/evojam;personal=/home/marcin/Projects;evojam=/home/marcin/Projects;parloa=/home/marcin/Projects;m1-personal=/home/marcin-personal/Projects;m1-evojam=/home/marcin-evojam/Projects;m1-parloa=/home/marcin-parloa/Projects"
        exec ${pkgs.claude-monitor}/bin/claude-monitor -addr :8787 -db /var/lib/claude-monitor/cm.db
      '';
      # systemd reads the sops secret as root and exposes it to the (dynamic)
      # service user under $CREDENTIALS_DIRECTORY — no world-readable copy.
      LoadCredential = [
        "monitor_token:/run/secrets/monitor_token"
        "llm_api_key:/run/secrets/llm_api_key"
        "llm_base_url:/run/secrets/llm_base_url"
      ];
      DynamicUser = true;
      StateDirectory = "claude-monitor"; # /var/lib/claude-monitor (db lives here)
      Restart = "on-failure";
      RestartSec = 2;
    };
  };

  # Orchestrator: a headless sidecar that watches the collector's /stream SSE,
  # triages blocked sessions through an LLM + policy (via the operator's LiteLLM
  # gateway), and relays to Slack (Socket Mode) with a live board. It is a plain
  # dashboard client over localhost:8787 — no new collector endpoints, no token
  # needed. Slack Socket Mode is an outbound WebSocket, so no inbound port either.
  systemd.services.claude-monitor-orchestrator = {
    description = "claude-monitor Slack session orchestrator";
    wantedBy = ["multi-user.target"];
    # Start after the collector so /stream is up (best-effort; the watcher
    # reconnects with backoff regardless).
    after = ["network.target" "claude-monitor.service"];
    wants = ["claude-monitor.service"];
    serviceConfig = {
      ExecStart = pkgs.writeShellScript "claude-monitor-orchestrator-start" ''
        export SLACK_BOT_TOKEN="$(cat "$CREDENTIALS_DIRECTORY/slack_bot_token")"
        export SLACK_APP_TOKEN="$(cat "$CREDENTIALS_DIRECTORY/slack_app_token")"
        export SLACK_CHANNEL_ID="$(cat "$CREDENTIALS_DIRECTORY/slack_channel_id")"
        export LLM_API_KEY="$(cat "$CREDENTIALS_DIRECTORY/llm_api_key")"
        export LLM_BASE_URL="$(cat "$CREDENTIALS_DIRECTORY/llm_base_url")"
        # Non-secret config (safe in the public repo).
        export LLM_MODEL="claude-sonnet-4-6"
        export COLLECTOR_BASE_URL="http://localhost:8787"
        # Personal task hub: dedicated Slack #tasks channel. Non-secret (a channel
        # id). Unset → the task module is fully disabled and the orchestrator
        # behaves as before. Optional overrides (DIGEST_TIMES, TASKS_TZ, AGING_DAYS,
        # CAPTURE_CONFIDENCE, COMPLETE_CONFIDENCE, FUZZY_*, SNOOZE_LATER_HOURS) use
        # built-in defaults (09:00,13:00,18:00 Europe/Warsaw).
        export TASKS_CHANNEL_ID="C0BK28132A0"
        # Per-machine workspace roots for natural-language launch ("run a session
        # on mac in platform-fe …"). Absolute paths on the TARGET machine; the
        # resolver joins a bare repo name onto the first root, so parloa is primary
        # (other dirs need a full path in the launch). These are mac's paths.
        # Deliberately mac-only, and deliberately NOT the same value as the
        # collector's WORKSPACE_ROOTS above: this one only backs natural-language
        # launch (mac is the only machine launched that way), while the
        # collector's drives the dashboard's project picker on all seven hosts.
        # Same variable name, two consumers — not a copy-paste slip.
        export WORKSPACE_ROOTS="mac=/Users/marcinwadon/Projects/parloa,/Users/marcinwadon/Projects/marcinwadon,/Users/marcinwadon/Projects/evojam"
        # Policy file is optional: a missing path falls back to the built-in
        # aggressive default. Drop a policy.md here to override.
        export POLICY_PATH="/var/lib/claude-monitor-orchestrator/policy.md"
        export ORCHESTRATOR_DB="/var/lib/claude-monitor-orchestrator/orchestrator.db"
        exec ${pkgs.claude-monitor}/bin/claude-monitor-orchestrator
      '';
      LoadCredential = [
        "slack_bot_token:/run/secrets/slack_bot_token"
        "slack_app_token:/run/secrets/slack_app_token"
        "slack_channel_id:/run/secrets/slack_channel_id"
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
