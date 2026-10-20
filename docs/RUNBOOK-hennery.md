# RUNBOOK — hennery collector + hosts, alongside claude-monitor

hennery v0.1.4 runs **next to** claude-monitor. It has its own collector on the
monitor box and its own host on the Mac and on the three M1 users. It shares no
unit, port, user or state directory with claude-monitor. The Proxmox CTs
(personal/evojam/parloa) are not part of this.

| Piece | Where | Unit | Files |
|---|---|---|---|
| package | everywhere | — | `system/pkgs/hennery.nix` (version + 3 hashes, one edit per bump) |
| collector | monitor box | `hennery-collector.service`, user `hennery`, `/var/lib/hennery` (0700) | `nixos/hennery.nix` |
| TLS proxy | monitor box | `caddy.service` on :443 → `127.0.0.1:7117` | `nixos/hennery/Caddyfile` (verbatim from the v0.1.4 tag) |
| certificate | monitor box | `acme-internal.wadon.net.service` + renew timer | `*.internal.wadon.net`, Let's Encrypt, DNS-01 via Cloudflare |
| host (Mac) | launchd agent | `org.nix-community.home.hennery-host-nix` | `home/programs/hennery-host/` |
| host (M1 ×3) | systemd --user | `hennery-host-nix.service` | same module |

**Never run `hennery service install|uninstall` on these machines.** hennery's
own service files have different names (`dev.hennery.host`,
`hennery-host.service`). `hennery-host-nix` is owned by home-manager, and a
second, hennery-installed host on the same data directory would compete with
it for the host lock.

**Exposure: LAN/WireGuard only, no per-client caps (decided 2026-10-20).**
hennery's proxy recipe asks for per-client connection/request caps in front of
Caddy before public exposure. They are deliberately skipped here: the name
resolves to a private address, it is reachable only from the LAN and over
WireGuard, and this CT lacks the `connlimit`/`hashlimit` netfilter matches
anyway. Revisit before :443 is ever reachable from outside that population.

## Order

Collector first, then hosts. A host cannot pair until the collector answers on
`https://hennery.internal.wadon.net`.

## Step 0 — operator, once, before any rebuild

1. **Cloudflare API token.** Create it with permissions **Zone / Zone / Read**
   and **Zone / DNS / Edit**, with zone resources limited to **wadon.net** only.
   lego needs both permissions: Zone:Read resolves the zone ID, DNS:Edit writes
   the `_acme-challenge` TXT record.
2. **sops.** Add one key to `secrets/monitor.yaml`. Its value is the raw token,
   not `KEY=value`:

   ```yaml
   cloudflare_dns_api_token: <the token>
   ```

   Only the monitor box's host key is a recipient, so edit from the Mac with:

   ```bash
   export SOPS_AGE_KEY=$(ssh root@10.0.1.123 'cat /etc/ssh/ssh_host_ed25519_key' | nix run nixpkgs#ssh-to-age -- -private-key)
   sops secrets/monitor.yaml
   ```

   Check that the key is present without printing the value. Expect a non-zero
   byte count:

   ```bash
   sops -d --extract '["cloudflare_dns_api_token"]' secrets/monitor.yaml | wc -c
   grep -c 'cloudflare_dns_api_token: ENC\[' secrets/monitor.yaml   # 1
   ```

   **This key is a hard precondition**: the monitor rebuild fails without it.
3. **DNS.** In Cloudflare, create `hennery.internal.wadon.net  A  10.0.1.123`,
   **DNS only** (grey cloud, not proxied). A public name that answers with a
   private address is often dropped by LAN resolvers (DNS-rebind protection).
   Check from the Mac and from the M1. Each must print `10.0.1.123`:

   ```bash
   dig +short hennery.internal.wadon.net
   ssh marcin@10.0.1.91 'getent hosts hennery.internal.wadon.net'
   ```

   If either is empty, allowlist `internal.wadon.net` in that resolver's
   rebind protection. The certificate is unaffected either way: lego asks
   1.1.1.1.
4. **Commit** `feat/hennery`, signed, including `secrets/monitor.yaml`. The M1
   ships with `git archive`, which only sees committed content.

## Step 1 — collector on the monitor box

The box's `/root/nix-config` is a hand-synced tree with no `.git`, and it lags
main. It pins claude-monitor at `fbf6b84`; main pins `ae2b520`. **Ship only
the files below and keep the box's own `flake.lock`.** Shipping main's lock
would also bump claude-monitor there, which is a separate deploy.

The change was checked by evaluating the box's actual tree plus these files.
Only `firewall.service` (adds 443) and `mandb.service` change. `claude-monitor`,
`claude-monitor-orchestrator` and marcin's home-manager generation keep their
current store paths, so they are **not restarted**.

```bash
# bash, from the feat/hennery checkout
FILES="system/pkgs/hennery.nix nixos/hennery.nix nixos/hennery/Caddyfile
home/programs/hennery-host/default.nix outputs/home-conf.nix nixos/envs/monitor.nix
home/programs/default.nix home/lib/profile-defaults.nix secrets/monitor.yaml"

# back up what will be overwritten (new files simply don't exist yet)
ssh root@10.0.1.123 "cd /root/nix-config && for f in $(echo $FILES); do [ -e \$f ] && cp -p \$f \$f.bak-pre-hennery; done; true"

COPYFILE_DISABLE=1 tar c $FILES | ssh root@10.0.1.123 'cd /root/nix-config && tar x'

# verify: every shipped file matches
for f in $FILES; do printf '%s  %s\n' "$(md5 -q $f)" "$f"; done > /tmp/hennery-ship.md5
ssh root@10.0.1.123 'cd /root/nix-config && md5sum -c' < /tmp/hennery-ship.md5
```

`home/lib/profile-defaults.nix` on the box was older than main (no
`memoryMcpTokenFile`). The shipped version is main plus the two hennery fields.
That is harmless there, because the monitor profile disables the claude-monitor
hook.

Rebuild detached. The box exceeds foreground timeouts, and an interrupted
switch leaves services stopped. The private `claude-monitor` input needs the
token even with an unchanged lock:

```bash
TOK=$(fish -c 'echo $GITHUB_TOKEN')   # marcinwadon (private claude-monitor); `gh auth token` may be the work account
[ -n "$TOK" ] || { echo "ERROR: empty gh token — stop"; exit 1; }
ssh root@10.0.1.123 "GHTOKEN='$TOK' bash -s" <<'EOF'
cd /root/nix-config
export NIX_CONFIG="access-tokens = github.com=$GHTOKEN"   # env, not argv: stays out of ps
setsid nohup bash -c 'nixos-rebuild switch --flake .#monitor --max-jobs 1 --cores 2; echo EXIT=$?' > /root/rebuild-hennery.log 2>&1 < /dev/null &
EOF
# poll until the EXIT= line appears
ssh root@10.0.1.123 'tail -3 /root/rebuild-hennery.log'
```

`EXIT=0` is expected. Caddy's module adds `net.core.{r,w}mem_max` sysctls. This
CT's `/proc/sys` is read-only, so `systemd-sysctl` skips them, as it already
does for the existing inotify keys. For a non-zero `EXIT`, run
`systemctl --failed` and read the log's tail. The likeliest cause is a failed
first ACME order (token scope, or the TXT record not visible). That leaves
Caddy on the placeholder certificate and does not affect claude-monitor.

Verify on the box:

```bash
ssh root@10.0.1.123 'bash -s' <<'EOF'
systemctl is-active hennery-collector caddy claude-monitor claude-monitor-orchestrator
# claude-monitor must NOT have restarted: its start time predates the rebuild
systemctl show -p ActiveEnterTimestamp claude-monitor claude-monitor-orchestrator
test -s /run/secrets/cloudflare_dns_api_token && echo "cf token present: $(wc -c < /run/secrets/cloudflare_dns_api_token) bytes"
systemctl status --no-pager acme-order-renew-internal.wadon.net | tail -5
ss -ltnp | grep -E ':(443|7117|2019|8787|8443) '
EOF
# from the Mac (the box has no openssl; macOS LibreSSL has no -ext, so grep -text):
echo | openssl s_client -connect 10.0.1.123:443 -servername hennery.internal.wadon.net 2>/dev/null > /tmp/sc.txt
openssl x509 -in /tmp/sc.txt -noout -issuer -subject -dates
openssl x509 -in /tmp/sc.txt -noout -text | grep -A1 'Subject Alternative Name'
curl -sS https://hennery.internal.wadon.net/healthz     # "ok", no -k
```

Expected results:

- The issuer is Let's Encrypt. `minica` means the self-signed placeholder is
  still in place: issuance hasn't succeeded yet.
- The SAN is `*.internal.wadon.net`.
- Listeners: 443 on 0.0.0.0 and `::`; 7117 and 2019 on loopback only.

If issuance failed (wrong token scope, or the DNS record missing), fix it, then
run `systemctl start acme-order-renew-internal.wadon.net`. Caddy keeps serving
the placeholder until then. Renewal reloads Caddy (`caddy reload --force`).

First-run setup. The link is valid for one hour:

```bash
ssh root@10.0.1.123 'cat /var/lib/hennery/setup-url'
# expired? mint a fresh one:
ssh root@10.0.1.123 'runuser -u hennery -- hennery admin --data-dir /var/lib/hennery setup-url'
```

Open the link, then set the owner password and passkey. **Back up**
`/var/lib/hennery/master.key` together with `hennery.db`.

## Step 2 — hosts

Each host is configured unpaired. The service starts, finds no `host.toml`, and
waits: systemd backs off from 5 s to 10 min, and the Mac wrapper sleeps 5 min
per try. Nothing blocks activation. Pairing is manual, once per host, against
the same data directory the unit uses.

Mint one pairing code per host. Codes are valid for 10 minutes:

```bash
ssh root@10.0.1.123 'runuser -u hennery -- hennery admin --data-dir /var/lib/hennery pairing-code'
```

`hennery host join` downloads the pinned adapter runtime (Node + the
claude/codex ACP adapters, digest-pinned) from nodejs.org and npm, so the host
needs outbound HTTPS.

### 2a — Mac

**Decide first:** `~/Library/Application Support/hennery` already holds a
`hennery up` test install from Oct 14 (`collector/`, `host/`, `up.lock`).
`host join` and `host run` refuse that directory while it holds an `up` layout,
and the agent waits. Move it aside (for example to
`hennery.up-test-20261014`) or delete it. That is your call; nothing here
touches it.

Run `./switch home` from the committed `feat/hennery` checkout, or from main
after merging, in a terminal that is **not** a claude-monitor-hosted session.
The Mac's live home generation is gen 63 (Oct 8), so this switch also applies
main's pending claude-monitor bump. That restarts `claude-monitor-host` and
parks its live ACP sessions; this change alone would not, since its
claude-monitor plists equal main's.

```bash
launchctl print gui/$(id -u)/org.nix-community.home.hennery-host-nix | grep -E 'state|last exit'
tail ~/Library/Logs/hennery-host-nix.log      # "no pairing … Checking again in 5 min."

hennery host join --name mac --data-dir "$HOME/Library/Application Support/hennery" https://hennery.internal.wadon.net
#   (type the pairing code when asked; it stays out of argv/history)
launchctl kickstart -k gui/$(id -u)/org.nix-community.home.hennery-host-nix
tail ~/Library/Logs/hennery/host.log
```

### 2b — M1 users (`m1-personal`, `m1-evojam`, `m1-parloa`)

Ship the committed branch to `/srv/nix-config` as in `RUNBOOK-m1-asahi.md`
Step 2a. Keep the same secret excludes, **plus `flake.lock`**: the M1 pins
claude-monitor at `b157744`, and keeping its lock means the M1's
claude-monitor units don't change. That was checked by evaluation: main and
this branch produce identical claude-monitor units under the M1 lock.

```bash
git archive --format=tar feat/hennery \
  | ssh marcin@10.0.1.91 "tar xf - -C /srv/nix-config \
      --exclude='home/secrets/*' --exclude='home/secrets' --exclude='home/scripts/h_*' \
      --exclude='flake.lock'"
ssh marcin@10.0.1.91 'ls /srv/nix-config/home/programs/hennery-host/default.nix && ls /srv/nix-config/home/secrets 2>&1 | head -1'
```

Give each user a short-lived token file for the private `claude-monitor`
input. **Do not re-run `RUNBOOK-m1-asahi.md` Step 2b**: it re-pulls signing
keys and monitor tokens from the CTs and overwrites them. From the Mac, in
`bash`:

```bash
GHTOK=$(fish -c 'echo $GITHUB_TOKEN')   # marcinwadon, not the gh keyring work account
[ -n "$GHTOK" ] || { echo "ERROR: empty gh token — stop"; exit 1; }
for c in personal evojam parloa; do
  ssh "marcin-$c@10.0.1.91" 'umask 077; cat > ~/.nixtok' <<< "access-tokens = github.com=$GHTOK"
done
```

Then, logged in as each user, run `RUNBOOK-m1-asahi.md` Step 3 unchanged. It
checks `~/.nixtok` and the existing token/key files, runs
`nix build "path:/srv/nix-config#homeConfigurations.m1-$c.activationPackage"
&& ./result/activate`, and shreds `~/.nixtok`. Expect
`hennery-host-nix.service` among the started units, and no
`claude-monitor-*` restart.

Then, as each user:

```bash
c="${USER#marcin-}"
systemctl --user status hennery-host-nix --no-pager | head -5   # activating (auto-restart), "holds no pairing"
hennery host join --name "m1-$c" --data-dir ~/.local/share/hennery https://hennery.internal.wadon.net
systemctl --user restart hennery-host-nix   # a manual start also resets the backoff
systemctl --user is-active hennery-host-nix
```

All three users share the hostname `mini`, so `--name m1-<client>` is what
keeps them apart in the collector's list.

Check from the box:

```bash
ssh root@10.0.1.123 'runuser -u hennery -- hennery admin --data-dir /var/lib/hennery hosts'
```

## Rollback

- **Box:** `nixos-rebuild switch --rollback` (detached, as above). To also
  restore the tree, move the `*.bak-pre-hennery` files back and delete the four
  new files.
- **Mac / M1:** activate the previous home-manager generation
  (`home-manager generations`, then `<path>/activate`).
- The hennery data directories survive rollback. Remove them only on purpose.

## Bumping hennery

Edit `system/pkgs/hennery.nix`: `version`, plus the three hashes from the new
release's `SHA256SUMS`. Take them only after the README's release-verification
block, adapted to the archives: signed tag, then `gh attestation verify` of
`SHA256SUMS` and of each archive. Then diff `packaging/proxy/Caddyfile` at the
new tag against `nixos/hennery/Caddyfile`, and `crates/hennery/src/service/unit.rs`
against `home/programs/hennery-host/default.nix`.

---

Generated with Claude AI — please review before distribution.
