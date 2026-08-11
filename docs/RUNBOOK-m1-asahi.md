# RUNBOOK — Mac mini M1 (Fedora Asahi Remix) fleet host

`mini` · `10.0.1.91` · Fedora Asahi Remix 44 Server · aarch64, **16K pages** ·
SELinux **enforcing** · users `marcin-{personal,evojam,parloa}` · dashboard
labels `m1-{personal,evojam,parloa}`.

Design: `docs/superpowers/specs/2026-08-11-m1-asahi-fleet-host-design.md`

## Facts that decide the procedure

- **Install Nix with `dnf`, never the nixos.org script** — the legacy installer
  deliberately aborts under SELinux enforcing. Fedora 44 packages Nix.
- **The 16K kernel is fine.** The 4K-built nixpkgs cache runs here, including
  node/V8 with JIT and the ACP adapter's prebuilt linux-arm64 SDK. `kernel`
  (4K) exists at the same version as `kernel-16k` and is a pure fallback; do
  not switch without a measured failure.
- **`nix-ld` is not needed.** Fedora is an ordinary glibc distribution, so
  `pkgs.claude-code` works directly. No native `~/.local/bin` install.
- **Signing keys are reused from the matching CT** — one key per client
  *identity*, not per machine. The key also serves GitHub authentication.
- **`/home/marcin` is mode `700`** (Fedora's `/etc/login.defs` sets
  `HOME_MODE 0700`, so `useradd -m` gives the three new users 700 homes too).
  A flake checkout inside anyone's home is therefore unreadable by the other
  two users — a `path:` flake ref there fails with `EACCES`, which reads like
  a nix problem, not a permissions one. The checkout lives at
  `/srv/nix-config` instead (see Step 1), outside every user's home, so this
  is a non-issue rather than a workaround. `/home/marcin` itself is left
  untouched.

## Already done (as of 2026-08-11)

The box is already provisioned with:
- Nix 2.34.8 installed via Fedora's `dnf` package
- `nix-daemon` systemd service active and enabled
- `~/.config/nix/nix.conf` on marcin's home already configured with `experimental-features = nix-command flakes`
- User `marcin` exists with SSH key in place

The three per-client users (`marcin-personal`, `marcin-evojam`, `marcin-parloa`) do **not** exist yet.
Everything below Step 1 onward is still pending.

## Step 1 — operator, as root (cannot be automated: sudo needs a password)

```bash
sudo dnf install -y nix
sudo systemctl enable --now nix-daemon

# One user per client identity.
for c in personal evojam parloa; do
  sudo useradd -m -s /bin/bash "marcin-$c"
done

# systemd user services must survive logout. Without this the ACP host runs
# only while an ssh session is open. The CTs get this from
# users.users.marcin.linger in nixos/lxc-base.nix, which does not exist here.
for c in personal evojam parloa; do
  sudo loginctl enable-linger "marcin-$c"
done

# Reuse marcin's authorized_keys so the fleet can reach each user.
for c in personal evojam parloa; do
  sudo install -d -m 700 -o "marcin-$c" -g "marcin-$c" "/home/marcin-$c/.ssh"
  sudo cp /home/marcin/.ssh/authorized_keys "/home/marcin-$c/.ssh/authorized_keys"
  sudo chown "marcin-$c:marcin-$c" "/home/marcin-$c/.ssh/authorized_keys"
  sudo chmod 600 "/home/marcin-$c/.ssh/authorized_keys"
done

# Place for the flake checkout, readable by all three users — see "Facts
# that decide the procedure" above for why this is NOT /home/marcin/nix-config.
# Owned by marcin (not root) so Step 2's tar-pipe, run as marcin, can write
# into it without sudo.
sudo mkdir -p /srv/nix-config
sudo chown marcin:marcin /srv/nix-config
sudo chmod 755 /srv/nix-config
```

Verify: `loginctl show-user marcin-parloa | grep Linger` prints `Linger=yes`,
`ssh marcin-parloa@10.0.1.91 true` succeeds from the Mac, and
`ssh marcin@10.0.1.91 'stat -c "%a %U" /srv/nix-config'` prints `755 marcin`.

## Step 2 — operator, from your Mac: ship the flake checkout

Run this from a terminal on your Mac (not an ssh session on the box) — it
reads the local working tree and streams it over:

```bash
cd /Users/marcinwadon/Projects/marcinwadon/nix-config
COPYFILE_DISABLE=1 tar czf - --exclude .git --exclude result . \
  | ssh marcin@10.0.1.91 'tar xzf - -C /srv/nix-config'
ssh marcin@10.0.1.91 'ls /srv/nix-config/home/profiles/m1-common.nix && echo staged-ok'
```

The tar carries the working tree, so the `git add -N` visibility problem does
not apply — but `path:` must be used as the flake ref below, since there is
no `.git` on the box.

## Step 3 — automatable, per user

SSH in as `marcin-personal@10.0.1.91` and run this block, then repeat unchanged
logged in as `marcin-evojam`, then `marcin-parloa`. The client identity is
derived from the account you run it as, so there is nothing to edit between
runs. The inner `ssh` calls below use `-n` deliberately — without it, a
piped/non-interactive invocation of this block can have the inner `ssh` steal
unread bytes from the outer script's own input stream, silently truncating
everything after it while still exiting 0.

```bash
# Flakes.
mkdir -p ~/.config/nix
printf "experimental-features = nix-command flakes\n" > ~/.config/nix/nix.conf

# Derive the client identity from the account this runs as. Usernames are marcin-<client>
# by construction. Nothing to edit — run this block unchanged as each user.
c="${USER#marcin-}"
case "$c" in
  personal|evojam|parloa) ;;
  *) echo "ERROR: run this as marcin-personal, marcin-evojam or marcin-parloa (got user '$USER')" >&2; exit 1 ;;
esac

# Monitor token (shared fleet-wide), 0600. Fetched from evojam's CT
# (10.0.1.121) regardless of which client `$c` is — the monitor token is one
# value shared across the whole fleet, not a per-client secret, so any CT
# would do here.
mkdir -p ~/.config/claude-monitor
TOKEN=$(ssh -n marcin@10.0.1.121 'cat /run/secrets/monitor_token') || { echo "ERROR: failed to fetch monitor token" >&2; exit 1; }
[ -n "$TOKEN" ] || { echo "ERROR: monitor token is empty" >&2; exit 1; }
install -m 600 /dev/stdin ~/.config/claude-monitor/token <<< "$TOKEN"

# Signing key, reused from the matching CT (personal .120, evojam .121, parloa .122).
case "$c" in
  personal) CONTAINER_IP=10.0.1.120 ;;
  evojam) CONTAINER_IP=10.0.1.121 ;;
  parloa) CONTAINER_IP=10.0.1.122 ;;
esac
KEY=$(ssh -n marcin@$CONTAINER_IP 'cat /run/secrets/ssh_signing_key') || { echo "ERROR: failed to fetch signing key from $CONTAINER_IP for client $c" >&2; exit 1; }
[ -n "$KEY" ] || { echo "ERROR: signing key is empty" >&2; exit 1; }
mkdir -p ~/.ssh && chmod 700 ~/.ssh
install -m 600 /dev/stdin ~/.ssh/id_ed25519_signing <<< "$KEY"

# Activate. Use the pinned home-manager revision from flake.lock, not the registry's
# unpinned home-manager/master, so the CLI version matches the configuration.
nix build "path:/srv/nix-config#homeConfigurations.m1-$c.activationPackage" && \
./result/activate
```

## Step 4 — operator, as root, once, after Step 3 has run for all three users

Fish is installed **by home-manager**, so it does not exist on the box until
each user's Step 3 activation has run — doing this before Step 3 would `chsh`
to a path that doesn't exist yet, and `chsh` refuses a shell absent from
`/etc/shells`. That is why this is its own step, sequenced *after* Step 3
rather than folded into Step 1: do not "tidy" it back to before activation.

```bash
for c in personal evojam parloa; do
  FISH=$(sudo -i -u "marcin-$c" command -v fish) || { echo "ERROR: fish not found for marcin-$c — did Step 3 activation succeed?" >&2; continue; }
  grep -qxF "$FISH" /etc/shells || echo "$FISH" | sudo tee -a /etc/shells >/dev/null
  sudo chsh -s "$FISH" "marcin-$c"
  echo "marcin-$c -> $FISH"
done
```

`sudo -i -u` requests a real login shell for the target user, which is what
makes their home-manager-managed `PATH` (and therefore `fish`) visible to
`command -v` — a bare `sudo -u` or a non-login `ssh user@host 'command'` would
not reliably see it. Only `sh` and `bash` are listed in `/etc/shells` by
default on this box, so `fish` must be appended before `chsh` will accept it.

Verify: `getent passwd marcin-parloa | cut -d: -f7` ends in `/fish`.

## Step 5 — operator, interactive, once per user (cannot be scripted)

```bash
ssh -t "marcin-$c@10.0.1.91" 'claude /login'
```

Until this is done, `session/prompt` fails with
`-32000 "Authentication required"`, which reads like a code bug and is not one.

While you're doing this per-user interactive pass, two more one-time,
per-user items belong here for the same reason:

- **`gh auth login`**, once per user. The reused ssh key covers git-over-ssh
  but not the `gh` CLI, which authenticates separately. (The CTs have the
  same gap — this is parity, not a regression introduced here.)
- **If `ssh marcin-$c@10.0.1.91 true` fails after Step 1** even though the
  key and `authorized_keys` look right, SELinux is very likely the cause —
  this box runs enforcing. The fix is
  `sudo restorecon -R -v /home/marcin-$c/.ssh`. An SELinux labelling failure
  on a copied `.ssh` directory presents as an authentication mystery, not as
  an obvious permissions error, so check this before re-checking the key
  material.

## Step 6 — collector

Deploy the `WORKSPACE_ROOTS` change and restart the collector on the monitor box
(`10.0.1.123`). Without it the project picker for the M1 hosts is silently empty.

## Verification (all four must pass)

1. `curl -s http://10.0.1.123:8787/api/machines` lists `m1-personal`,
   `m1-evojam`, `m1-parloa` alongside the existing four.
2. `curl -s -o /dev/null -w '%{http_code}' http://10.0.1.123:8787/api/machines/m1-parloa/projects`
   returns `200` and the machine is listed in step 1's output. This is
   deliberately NOT "the list is non-empty": on a fresh user `~/Projects`
   does not exist yet, and the enumerator skips a missing root rather than
   erroring, so an empty `[]` here is expected until a repo is cloned into
   `~/Projects` on that user — it does not mean `WORKSPACE_ROOTS` is wrong.
3. Start a session on `m1-parloa` from the dashboard, send a prompt, get a reply.
4. That session appears under the **Parloa** hat, not Personal.

## Maintenance notes

- Three home-manager generations. A shared-module change needs three `switch`
  runs on this box, not one.
- Kernel updates come from Asahi, outside git. If a *new* dependency could bake
  page size at build time, re-probe rather than assume — see the probe set in
  the design document.
- Nix itself is Fedora-packaged, so `dnf upgrade` moves it. Unusual for this
  fleet; the CTs pin Nix through NixOS.
