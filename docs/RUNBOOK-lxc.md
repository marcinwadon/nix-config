# Proxmox NixOS LXC — provisioning runbook

## Build the template (on the Proxmox host)
1. Install Nix on the host (Determinate installer) and enable flakes.
2. Clone this repo, then: `./switch template` (= `nix build .#packages.x86_64-linux.lxcTemplate`).
3. The artifact is at `./result/tarball/*.tar.xz`. Copy it to
   `/var/lib/vz/template/cache/` (or import via the Proxmox UI).

## Create a container (repeat per env)
- `pct create <vmid> local:vztmpl/<template>.tar.xz \
     --hostname <env> --unprivileged 1 --features nesting=1 \
     --net0 name=eth0,bridge=vmbr0,ip=dhcp --cores 4 --memory 8192 --rootfs local-lvm:32`
- Start it; add your Mac's SSH public key to `nixos/lxc-base.nix`
  (`users.users.marcin.openssh.authorizedKeys.keys`) before the first rebuild,
  or inject it via `pct push`.

## First-boot bootstrap (inside each CT)
1. `pct enter <vmid>` (or SSH in).
2. Get the age recipient from the host key:
   `nix-shell -p ssh-to-age --run 'ssh-to-age < /etc/ssh/ssh_host_ed25519_key.pub'`
3. On your workstation: paste that age key into `.sops.yaml` for this env,
   replacing the matching `age1PLACEHOLDER_*`.
4. Create the env's secrets file: `sops secrets/<env>.yaml` → add keys:
   - `github_token`: a GitHub PAT for this env's account.
   - `ssh_signing_key`: a NEW ed25519 PRIVATE key (`ssh-keygen -t ed25519 -f key -N ""` → paste contents of `key`).
   - `ssh_signing_key.pub`: the matching PUBLIC key.
   - `allowed_signers`: `<git-email> <contents-of-ssh_signing_key.pub>`
   Commit the encrypted `secrets/<env>.yaml` and the updated `.sops.yaml`.
5. Add `ssh_signing_key.pub` to this env's GitHub account as BOTH an
   Authentication key and a Signing key.
6. In the CT: clone this repo, then `./switch nixos <env>`
   (= `sudo nixos-rebuild switch --flake .#<env>`).
7. Verify: `gh auth status`, then
   `git commit --allow-empty -m sig-test && git log --show-signature -1`.

## Iterate
- Edit the flake, then `./switch nixos <env>` inside the CT.
