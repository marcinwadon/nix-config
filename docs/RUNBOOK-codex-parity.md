# Runbook — rolling the Codex config out to the fleet

`home/programs/codex/` gives Codex the same memory, skills and workflows Claude
Code has. It is home-manager only: no new secret, no system rebuild, no service.

Applied on the Mac already (`./switch home`). Everything below is the rest of the
fleet. Each host needs **one Yubikey touch** for the SSH key, which is why this
is a runbook and not a script the assistant can run unattended.

## What has to reach each host

Four files, all under `home/`:

```
home/programs/codex/default.nix                                   (new)
home/programs/codex/files/AGENTS.md                               (new)
home/programs/default.nix                                         (adds ./codex)
home/programs/claude-code/files/skills/fix-dependabot-alerts/SKILL.md  (new)
```

`/root/nix-config` on the hosts has drifted per host, so **back the files up
before overwriting and check the one modified file for drift**:

```bash
ssh root@$IP 'cd /root/nix-config && git diff --stat 2>/dev/null; \
  md5sum home/programs/default.nix'
```

Compare that checksum against the Mac's pre-change version
(`git show HEAD~1:home/programs/default.nix | md5sum`). If it differs, hand-apply
the one-line `./codex` addition on that host instead of copying the file.

## LXC hosts (personal .120, evojam .121, parloa .122, monitor .123)

```bash
cd ~/Projects/marcinwadon/nix-config
for IP in 10.0.1.120 10.0.1.121 10.0.1.122 10.0.1.123; do
  ssh root@$IP 'cd /root/nix-config && cp home/programs/default.nix home/programs/default.nix.bak-pre-codex'
  COPYFILE_DISABLE=1 tar cf - \
    home/programs/codex \
    home/programs/default.nix \
    home/programs/claude-code/files/skills/fix-dependabot-alerts \
  | ssh root@$IP 'tar xf - -C /root/nix-config'
done
```

Then rebuild each (`.#personal`, `.#evojam`, `.#parloa`, `.#monitor`):

```bash
ssh root@10.0.1.121 'cd /root/nix-config && nixos-rebuild switch --flake .#evojam --max-jobs 1 --cores 2'
```

A failed rebuild leaves the running system untouched.

## M1 (`mini`, 10.0.1.91) — three users

The flake is at **`/srv/nix-config`** (not `/root`), and each user activates
standalone home-manager. The token is needed because the `claude-monitor` flake
input is a private repo.

```bash
COPYFILE_DISABLE=1 tar cf - home/programs/codex home/programs/default.nix \
  home/programs/claude-code/files/skills/fix-dependabot-alerts \
  | ssh root@10.0.1.91 'tar xf - -C /srv/nix-config'

TOK=$(gh auth token)
ssh root@10.0.1.91 "GHTOKEN='$TOK' bash -s" <<'REMOTE'
for c in personal evojam parloa; do
  runuser -u marcin-$c -- bash -lc "export NIX_CONFIG='access-tokens = github.com=$GHTOKEN'; \
    cd \$HOME && nix build 'path:/srv/nix-config#homeConfigurations.m1-$c.activationPackage' \
    && ./result/activate"
done
REMOTE
```

## Verify (per host / per user)

`systemctl`-style "it's active" proves nothing here. Check the artefacts:

```bash
# the routing file is a store symlink
ls -l ~/.codex/AGENTS.md
# eight personal skills beside Codex's own .system set
ls ~/.codex/skills
# memory is writable from a session running inside a repo
grep -A2 'sandbox_workspace_write' ~/.codex/config.toml
```

And the behavioural check, which is the one that matters — from inside any repo:

```bash
codex exec "Kim jestem i gdzie pracuję? Odpowiedz jednym zdaniem."
```

It should read `~/.claude/rules/memory-profile.md` and answer from it. If it
answers without reading anything, `~/.codex/AGENTS.md` did not load.

## Known caveat — the Mac's `~/.claude` is still the live copy

`home/programs/claude-code/files/` is authoritative for **Codex everywhere**, and
for **Claude on the CTs** (where `shareClaudeConfig = true` symlinks
`~/.claude/{skills,commands}` out of the repo).

On the **Mac** it is not: `shareClaudeConfig = false`, so Claude keeps reading the
live, hand-editable `~/.claude/skills` and `~/.claude/commands`, while Codex reads
the derivation built from the repo. They were made byte-identical by hand when
this landed — that is a snapshot, not a mechanism. Edit a live command on the Mac
and Codex will keep serving the older body, silently.

Two ways out, both the operator's call:

1. Accept it, and copy into `home/programs/claude-code/files/` when editing a
   command or skill on the Mac.
2. Link **only** `~/.claude/skills` and `~/.claude/commands` on the Mac (not the
   whole `shareClaudeConfig`, which would also capture `CLAUDE.md` and
   `agents/`). Small diff — but it turns files that are edited by hand today into
   read-only store symlinks.
