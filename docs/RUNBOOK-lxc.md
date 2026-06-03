# Proxmox NixOS LXC — Claude-coding environments runbook

Three reproducible NixOS LXC containers — `personal`, `evojam`, `parloa` — defined
as `nixosConfigurations` in this flake. Each composes `nixos/lxc-base.nix` + a
per-env module in `nixos/envs/`. Secrets are sops-encrypted **per container**,
decrypted at activation via that container's own SSH host key. Commit signing is
SSH-based with a per-env key; GitHub auth reuses the same key. **No GitHub token
is stored** — use `gh auth login`.

## 0. Build host (prerequisite)

The Mac is aarch64; the template and systems are `x86_64-linux` and must be built
on an x86_64 Linux box. If you can't install Nix on the Proxmox host, use a small
dedicated x86_64 Debian "nix-builder" CT.

Install Nix on the builder (Determinate installer). In an unprivileged LXC its
multi-user build-user creation can fail (`useradd: UID … is not unique`) — a
working `nix` is still installed, just write `/etc/nix/nix.conf`:

```
experimental-features = nix-command flakes
build-users-group = nixbld
max-jobs = auto
cores = 0
```

Sanity check: `nix build nixpkgs#hello`.

## 1. Build the LXC template (on the builder)

Get the flake onto the builder (rsync — see §3), then:

```
nix build "path:.#packages.x86_64-linux.lxcTemplate"
```

Artifact: `./result/tarball/*.tar.xz`. Copy it to Proxmox CT-template storage
(`/var/lib/vz/template/cache/`) or upload via the UI (Datacenter → node → storage
→ CT Templates → Upload).

The template bakes in: flakes enabled, openssh, the `marcin` user **with your Mac's
SSH public key**, `git`, `ssh-to-age`.

## 2. Create a container (per env)

```
pct create <vmid> local:vztmpl/<template>.tar.xz \
  --hostname claude-<env> --unprivileged 1 --features nesting=1 \
  --ostype unmanaged --cores <n> --memory <mb> \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp --rootfs <storage>:<gb>
pct start <vmid>
```

Reach it via `pct enter <vmid>` (console, always works) or `ssh root@<ip>` /
`ssh marcin@<ip>`.

## 3. Distribute the flake to the container

Primary method — rsync from the Mac. The excludes keep `.git`, the git-crypt key
material, and Mac-only secrets off the container (no git-crypt'd content ever
reaches a container):

```
rsync -az --delete \
  --exclude='/.git' --exclude='/.git-crypt' --exclude='/home/secrets' \
  --exclude='/home/scripts/h_*' --exclude='/result' --exclude='/.direnv' \
  --exclude='/.superpowers' --exclude='/.claude' \
  ./ root@<ip>:/root/nix-config/
```

Alternative — `git clone` the (public) repo on the CT. Works, but you then manage
secret edits + commits from the CT, and re-syncing config changes is a `git pull`.

## 4. Per-container sops bootstrap (one-time)

Secrets are encrypted to the container's SSH host key — no separate age key to
store.

1. On the CT, derive its age recipient:
   `ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub`
2. On the Mac, set that recipient in `.sops.yaml` (repo root) for the env —
   replace the `age1PLACEHOLDER_<ENV>` anchor.
3. Generate a per-env ed25519 key (used for **both** commit signing and GitHub auth):
   `ssh-keygen -t ed25519 -f /tmp/<env>_signing -N "" -C "marcin-<env>-claude-env"`
4. Create and encrypt `secrets/<env>.yaml`:
   ```
   ssh_signing_key: |
     <contents of /tmp/<env>_signing>          # the PRIVATE key, indented 2 spaces
   allowed_signers: "<git-email> <contents of /tmp/<env>_signing.pub>"
   ```
   `nix run nixpkgs#sops -- -e -i secrets/<env>.yaml`
   Shred the temp private key. Commit the encrypted `secrets/<env>.yaml` + `.sops.yaml`.
5. Add `/tmp/<env>_signing.pub` to the env's GitHub account **twice**:
   - as an **Authentication key** — required for `git clone`/push over SSH;
   - as a **Signing key** — for Verified commits.

## 5. Activate

rsync the updated flake (§3), then on the CT:

```
sudo nixos-rebuild switch --flake .#<env>     # or: ./switch nixos <env>
```

sops decrypts to `/run/secrets/{ssh_signing_key,allowed_signers}` (owner `marcin`,
mode 0400). Verify:

```
ssh -T git@github.com          # -> "Hi <account>! You've successfully authenticated"
cd /tmp && git init -q t && cd t && git commit --allow-empty -m sig-test \
  && git log --show-signature -1     # -> "Good git signature for <email>"
```

## 6. GitHub auth for HTTPS / gh

No token is baked in. In the container: `gh auth login`.

## 7. Native `claude`

`nixos/lxc-base.nix` enables `nix-ld` and `home.sessionPath` puts `~/.local/bin`
first on PATH, so the native installer's binary runs (NixOS can't run generic
dynamically-linked executables without nix-ld) and shadows the Nix `claude-code`.
Run the native installer; `claude --version` should work. If a binary needs a
library nix-ld doesn't provide, add it to `programs.nix-ld.libraries`.

## 8. Iterate

Edit the flake on the Mac → rsync (§3) → `./switch nixos <env>` on the CT.

## Notes & gotchas

- **`.sops.yaml` is at the repo root** (standard sops discovery).
- **Editing an existing secret**: each file is encrypted only to its container's
  host key, so the Mac can't decrypt it to edit. To change a secret, either edit
  on the CT (derive an age key from the host key) or add an admin age recipient
  you hold to `.sops.yaml` and re-encrypt. The leftover unused `github_token` key
  in the encrypted files is inert.
- **SSH signing ≠ SSH auth**: signing uses `user.signingkey` = the private-key
  path; cloning needs the same key offered to GitHub via the `github.com`
  `IdentityFile` matchBlock (in `home/profiles/common.nix`) **and** the pubkey
  registered as an Authentication key.
- **Darwin-only**: the `GITHUB_TOKEN` env var and the Constellation `h_*` scripts
  exist only on the Mac config; containers deliberately don't get them.
- **CI guard**: `nix flake check` runs `checks.aarch64-darwin.no-linux-secret-leak`,
  which fails if any container's fish config ever contains a token literal or
  `gpgconf`.

---

*Generated with Claude AI — please review before distribution.*
