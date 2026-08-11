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

## Step 2 — operator, from your Mac: ship the checkout and the secrets

Everything here runs on your Mac, not in an ssh session on the box, and it has
to: the Mac is the only machine holding both the git-crypt keys and ssh
credentials for the containers. **The three new users have no outbound ssh
identity at all** — their identity *is* the signing key being installed here,
so they cannot fetch it themselves. That circularity is why the secrets are
pushed from here instead of pulled by the per-user block.

### 2a — the flake checkout

```bash
cd /Users/marcinwadon/Projects/marcinwadon/nix-config
git archive --format=tar HEAD \
  | ssh marcin@10.0.1.91 "tar xf - -C /srv/nix-config \
      --exclude='home/secrets/*' --exclude='home/secrets' --exclude='home/scripts/h_*'"
ssh marcin@10.0.1.91 'ls /srv/nix-config/home/profiles/m1-common.nix && echo staged-ok'
```

Two details are load-bearing, both learned by failing:

**`git archive`, not `tar` of the working tree.** `tar` preserves the Mac's file
modes, and ~32 files under `home/programs/claude-code/files/` are mode `700`
there — the new users cannot read them, and the build fails with
`Permission denied` on `CLAUDE.md` while merely *fetching* the flake input.
`git archive` emits only git's exec bit, so everything lands readable. It also
ships committed content only, which excludes in-flight work in the tree.

**The excludes are a secret guard, not tidiness.** git-crypt protects
`home/secrets/**` and `home/scripts/h_*`, but those are *decrypted* in the
working tree, and `git archive` does **not** re-encrypt them — verified;
assuming it would is a mistake. Without the excludes the box receives your
GitHub tokens and OpenAI key in plaintext and world-readable. Nothing here
needs them: every consumer of those paths is Darwin-only.

Verify — expect *no such directory* and `0`:

```bash
ssh marcin@10.0.1.91 'ls /srv/nix-config/home/secrets 2>&1 | head -1; find /srv/nix-config \! -perm -o+r | wc -l'
```

### 2b — the secrets, pushed to each user

**Run this in `bash`** — your Mac's login shell is fish, where `$(...)`, `<<<`
and `$1` do not mean what this block needs. Type `bash` first.

```bash
TOKEN=$(ssh -n marcin@10.0.1.121 'cat /run/secrets/monitor_token')
[ -n "$TOKEN" ] || echo "ERROR: monitor token empty — stop here, do not continue"
GHTOK=$(gh auth token)

for pair in "personal 10.0.1.120" "evojam 10.0.1.121" "parloa 10.0.1.122"; do
  c=$(echo $pair | cut -d' ' -f1); ip=$(echo $pair | cut -d' ' -f2)
  KEY=$(ssh -n marcin@$ip 'cat /run/secrets/ssh_signing_key')
  [ -n "$KEY" ] || { echo "ERROR: $c key empty from $ip — skipping"; continue; }
  printf 'marcin-%-9s from %s -> ' "$c" "$ip"
  ssh "marcin-$c@10.0.1.91" 'umask 077; mkdir -p ~/.config/claude-monitor ~/.config/nix ~/.ssh; cat > ~/.config/claude-monitor/token' <<< "$TOKEN"
  ssh "marcin-$c@10.0.1.91" 'umask 077; cat > ~/.ssh/id_ed25519_signing' <<< "$KEY"
  ssh "marcin-$c@10.0.1.91" 'umask 077; cat > ~/.nixtok' <<< "access-tokens = github.com=$GHTOK"
  ssh "marcin-$c@10.0.1.91" 'printf "experimental-features = nix-command flakes\n" > ~/.config/nix/nix.conf; ssh-keygen -y -f ~/.ssh/id_ed25519_signing >/dev/null && echo "installed, key valid"'
done
```

Each identity gets **its own** key, from its own container — that mapping is the
whole point of reusing them, so a wrong pairing would silently sign as the wrong
person. Verify: three `installed, key valid` lines.

`~/.nixtok` exists because `claude-monitor` is a **private** flake input and
nix's `github:` fetcher needs an *https token* for it; an ssh key does not help,
and without it the build fails with a bare `HTTP error 404`. It is written
`0600`, Step 3 shreds it after use, and it is deliberately not passed on a
command line where `ps` would expose it.

## Step 3 — automatable, per user

SSH in as `marcin-personal@10.0.1.91` and run this block, then repeat unchanged
logged in as `marcin-evojam`, then `marcin-parloa`. The client identity is
derived from the account you run it as, so there is nothing to edit between
runs. This block fetches nothing — Step 2b already placed everything it needs,
because this account has no way to reach the containers.

```bash
# Derive the client identity from the account this runs as. Usernames are marcin-<client>
# by construction. Nothing to edit — run this block unchanged as each user.
c="${USER#marcin-}"
case "$c" in
  personal|evojam|parloa) ;;
  *) echo "ERROR: run this as marcin-personal, marcin-evojam or marcin-parloa (got user '$USER')" >&2; exit 1 ;;
esac

# Step 2b must have run for this user. Refuse to continue on a missing or empty
# file rather than activating a host that can never register: an unreadable
# token leaves MONITOR_TOKEN silently unset and the host simply never appears.
for f in ~/.config/claude-monitor/token ~/.ssh/id_ed25519_signing ~/.nixtok; do
  [ -s "$f" ] || { echo "ERROR: $f is missing or empty — run Step 2b from the Mac first" >&2; exit 1; }
done
chmod 700 ~/.ssh

# Activate with the pinned home-manager revision from flake.lock, not the
# registry's unpinned home-manager/master, so the CLI matches the configuration.
# NIX_CONFIG carries the https token the PRIVATE claude-monitor input needs.
export NIX_CONFIG="$(cat ~/.nixtok)"
nix build "path:/srv/nix-config#homeConfigurations.m1-$c.activationPackage" && ./result/activate
rc=$?
shred -u ~/.nixtok 2>/dev/null || rm -f ~/.nixtok
[ $rc -eq 0 ] || { echo "ERROR: build or activation failed for m1-$c — see output above" >&2; exit 1; }

# The project picker lists git repos under this root; it stays empty until you
# clone something, which is expected and not a WORKSPACE_ROOTS problem.
mkdir -p ~/Projects
echo "m1-$c activated"
```

Expect `Starting units: claude-monitor-host.service, claude-monitor-tail.service`
near the end of the activation output, then `m1-$c activated`. The token file is
shredded whether the build succeeded or not.

## Step 4 — operator, as root, once, after Step 3 has run for all three users

Fish is installed **by home-manager**, so it does not exist on the box until
each user's Step 3 activation has run. That is why this is its own step,
sequenced *after* Step 3 rather than folded into Step 1.

**Do not `chsh` straight to the nix-store fish.** It looks right and it locks
every account out. Two independent reasons, both found by doing it:

1. **SELinux is enforcing here, and it will not let `sshd` exec a `/nix/store`
   binary as a login shell.** Store files are labelled `default_t`; Fedora's
   policy wants a login shell to be `shell_exec_t` (`/bin/bash` is). The
   symptom is a bare `…/bin/fish: Permission denied` at login, which reads like
   a file-permission problem and is not one. The NixOS containers never showed
   this because NixOS carries no such policy.
2. **Nothing on the fish path sources `/etc/profile.d/nix.sh`**, so fish starts
   without `~/.nix-profile/bin` and loses `git`, `tmux`, `fzf`, `direnv` and
   `any-nix-shell` — a wall of `Unknown command` on every login.

Use a shim in `/usr/local/bin` instead. That directory is `bin_t`, which *is*
acceptable as a login shell (`/bin/sh` is `bin_t` too), and the shim runs as the
user, where exec'ing a store binary is allowed:

```bash
sudo tee /usr/local/bin/fish-login >/dev/null <<'W'
#!/bin/sh
# Login-shell shim for the nix-managed users. SELinux will not let sshd exec a
# /nix/store binary (default_t) as a login shell; /usr/local/bin is bin_t, which
# is acceptable. Sourcing nix.sh is what puts ~/.nix-profile/bin on PATH — fish
# would otherwise start without git/tmux/fzf/direnv/any-nix-shell. Falls back to
# bash so a broken or missing nix profile can never lock the account out.
[ -r /etc/profile.d/nix.sh ] && . /etc/profile.d/nix.sh
F="$HOME/.nix-profile/bin/fish"
[ -x "$F" ] && exec "$F" "$@"
exec /bin/bash "$@"
W
sudo chmod 755 /usr/local/bin/fish-login
sudo restorecon -v /usr/local/bin/fish-login
grep -qxF /usr/local/bin/fish-login /etc/shells || echo /usr/local/bin/fish-login | sudo tee -a /etc/shells >/dev/null
for c in personal evojam parloa; do sudo chsh -s /usr/local/bin/fish-login "marcin-$c"; done
```

One shim serves all three users: `$HOME` is set by `sshd` before the login shell
runs, so the same file resolves each user's own profile.

The bash fallback is deliberate and worth keeping. A login shell is the one
thing on a box you cannot afford to get wrong — if it fails you cannot log in to
fix it. Recovery, should you ever need it, is `ssh marcin@10.0.1.91` (whose
shell is untouched) and `sudo chsh -s /bin/bash marcin-<client>`.

Verify — each user should report the shim, all five tools, and a fish version:

```bash
for c in personal evojam parloa; do
  ssh "marcin-$c@10.0.1.91" 'echo $SHELL; for t in git tmux fzf direnv any-nix-shell; type -q $t; or echo "MISSING: $t"; end; fish --version'
done
```

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
