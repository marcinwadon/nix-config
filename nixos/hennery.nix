# hennery collector on the monitor box, behind Caddy on :443. Runs ALONGSIDE
# claude-monitor (nixos/envs/monitor.nix): different user, state directory,
# ports and units; nothing here touches the claude-monitor services.
#
#   browser / hosts --https/wss--> Caddy :443 --http--> 127.0.0.1:7117 collector
#
# TLS: one Let's Encrypt wildcard for *.internal.wadon.net, by DNS-01 against
# Cloudflare (the name only resolves on the LAN, so HTTP-01 is impossible).
# Caddy reads the files the ACME module writes and does no ACME itself.
{
  config,
  pkgs,
  ...
}: let
  dataDir = "/var/lib/hennery";
  backendPort = 7117;
  publicUrl = "https://hennery.internal.wadon.net";
  certName = "internal.wadon.net";
  certDir = "/var/lib/acme/${certName}";

  # The collector refuses a config.toml that its group or others can write;
  # a store file is 0444, so this one passes. Unknown keys are refused too, so
  # a typo stops the start instead of being ignored.
  configToml = pkgs.writeText "hennery-config.toml" ''
    listen = ["127.0.0.1:${toString backendPort}"]
    public_url = "${publicUrl}"
    # The only proxy is Caddy on this box; it overwrites Hennery-Client-IP with
    # the TCP peer. Trust that header from loopback and nowhere else.
    proxy_client_ip_peers = ["127.0.0.1"]
  '';

  # hennery's tested same-machine recipe, verbatim from the v0.1.4 tag
  # (packaging/proxy/Caddyfile; byte-identical on main at the time of writing).
  # Only its placeholders are filled in; replaceVars fails the build if one is
  # left over. Keep it in sync with the recipe on a hennery bump.
  caddyfile = pkgs.replaceVars ./hennery/Caddyfile {
    ADMIN_PORT = "2019"; # loopback-only admin API; `caddy reload` uses it
    TLS_PORT = "443";
    BIND_V4 = "0.0.0.0";
    BIND_V6 = "::";
    BACKEND_PORT = toString backendPort;
    CERT = "${certDir}/fullchain.pem";
    KEY = "${certDir}/key.pem";
  };
in {
  # Raw API token as the whole value (no KEY= prefix): Zone:Zone:Read +
  # Zone:DNS:Edit on wadon.net. Root-only; lego gets it as a systemd credential.
  sops.secrets.cloudflare_dns_api_token = {};

  users.users.hennery = {
    isSystemUser = true;
    group = "hennery";
    home = dataDir;
  };
  users.groups.hennery = {};

  # The CLI, for `sudo -u hennery hennery admin --data-dir /var/lib/hennery …`.
  environment.systemPackages = [pkgs.hennery];

  systemd.services.hennery-collector = {
    description = "hennery collector";
    wantedBy = ["multi-user.target"];
    after = ["network.target"];
    # As hennery's own collector unit.
    startLimitIntervalSec = 300;
    startLimitBurst = 10;
    serviceConfig = {
      Type = "exec";
      User = "hennery";
      Group = "hennery";
      # The database holds what only this user may read: 0700.
      StateDirectory = "hennery";
      StateDirectoryMode = "0700";
      # As root ("+"), after StateDirectory exists: point config.toml at the
      # store file. Part of the unit, so a config change restarts the collector.
      ExecStartPre = "+${pkgs.coreutils}/bin/ln -sfn ${configToml} ${dataDir}/config.toml";
      # HENNERY_SERVICE is deliberately unset: the collector then logs to
      # stdout, i.e. the journal, rather than under a system user's $HOME.
      ExecStart = "${pkgs.hennery}/bin/hennery collector --data-dir ${dataDir}";
      Restart = "on-failure";
      RestartSec = 3;
      KillMode = "mixed";
      TimeoutStopSec = 30;
      NoNewPrivileges = true;
      PrivateTmp = true;
      ProtectSystem = "strict";
      ProtectHome = true;
    };
  };

  security.acme = {
    acceptTerms = true;
    certs.${certName} = {
      domain = "*.${certName}";
      dnsProvider = "cloudflare";
      # Ask a public resolver: a LAN split-horizon view of internal.wadon.net
      # must not fail lego's propagation check.
      dnsResolver = "1.1.1.1:53";
      credentialFiles.CF_DNS_API_TOKEN_FILE = config.sops.secrets.cloudflare_dns_api_token.path;
      group = config.services.caddy.group;
      # `caddy reload --force` (the module's ExecReload) re-reads the new files.
      reloadServices = ["caddy.service"];
    };
  };

  services.caddy = {
    enable = true;
    configFile = caddyfile;
  };
  # Our own configFile bypasses the module's useACMEHost wiring, so order Caddy
  # after the cert unit by hand: that unit lays down a self-signed placeholder
  # before the first real issuance, so Caddy always has files to load.
  systemd.services.caddy = {
    wants = ["acme-${certName}.service"];
    after = ["acme-${certName}.service"];
  };

  # 443 only; claude-monitor's 8787/8443 stay as declared in monitor.nix (the
  # lists merge). No per-client connection caps: see the deploy notes.
  networking.firewall.allowedTCPPorts = [443];
}
