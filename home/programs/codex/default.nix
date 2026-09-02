{
  pkgs,
  lib,
  ...
}: let
  claudeFiles = ../claude-code/files;

  commandNames =
    map (f: lib.removeSuffix ".md" f)
    (builtins.attrNames
      (lib.filterAttrs (n: t: t == "regular" && lib.hasSuffix ".md" n)
        (builtins.readDir (claudeFiles + "/commands"))));

  # Codex 0.148 has no `~/.codex/prompts` (no custom slash commands): the native
  # home for a reusable workflow is a skill. So the Claude Code commands are
  # DERIVED into Codex skills at build time rather than copied — one source file
  # per workflow, so there is no second body to drift.
  #
  # The commands carry no frontmatter (Claude Code derives the description from
  # the first line) and use `$ARGUMENTS`, for which Codex has no substitution
  # layer. So synthesise the frontmatter, and prepend one instruction telling the
  # model to substitute the invocation argument itself.
  commandSkills = pkgs.runCommand "codex-command-skills" {} ''
    mkdir -p $out
    for f in ${claudeFiles}/commands/*.md; do
      name=$(basename "$f" .md)
      mkdir -p "$out/$name"
      # First line = the human summary. Strip surrounding blanks, neutralise the
      # placeholder so it reads as prose, then escape for a quoted YAML scalar.
      desc=$(head -n 1 "$f" \
        | sed -e 's/\$ARGUMENTS/<argument>/g' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
        | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
      {
        echo '---'
        echo "name: $name"
        echo "description: \"$desc Use when the user asks for this workflow by name.\""
        echo '---'
        echo
        echo 'The value the user passed when invoking this skill appears below as'
        echo '`$ARGUMENTS`. Substitute that value everywhere the placeholder occurs,'
        echo 'including inside shell commands. If the user gave no argument and a'
        echo 'step needs one, ask for it before running that step.'
        echo
        cat "$f"
      } > "$out/$name/SKILL.md"
    done
  '';

  # Already authored as SKILL.md — shared verbatim with Claude Code. Derived, not
  # listed, so a skill added for Claude reaches Codex without a second edit.
  sharedSkillDirs =
    builtins.attrNames
    (lib.filterAttrs (_: t: t == "directory")
      (builtins.readDir (claudeFiles + "/skills")));

  mkLink = name: source: {
    inherit name;
    value = {inherit source;};
  };

  skillLinks = lib.listToAttrs (
    (map (n: mkLink ".codex/skills/${n}" (claudeFiles + "/skills/${n}")) sharedSkillDirs)
    ++ (map (n: mkLink ".codex/skills/${n}" "${commandSkills}/${n}") commandNames)
  );

  # Codex reads `~/.codex/AGENTS.md` as global (per-developer) guidance. Like the
  # Claude Code CLAUDE.md this is a ROUTING file: the durable rules and memory
  # live in ~/.claude/rules/*.md and are shared by both assistants, so a fact
  # learned in one session is available in the other. Deliberately NOT a copy of
  # those rules — a copy in the nix store would go stale the moment the
  # auto-update memory rule appends to the live files.
  #
  # Skills are linked as individual entries so ~/.codex/skills stays a real
  # writable directory, shared with Codex's own `.system` skills and whatever
  # its skill-installer drops there.
  files = {".codex/AGENTS.md" = {source = ./files/AGENTS.md;};} // skillLinks;

  # Both skill sets are derived, and listToAttrs would silently keep only the
  # last entry for a shared name — so fail the build instead of shipping one
  # workflow that quietly shadowed another.
  clash = lib.intersectLists sharedSkillDirs commandNames;
in
  assert lib.assertMsg (clash == [])
  "codex: a skill and a command share a name: ${lib.concatStringsSep ", " clash}"; {
    home.file = files;

    # Codex sandboxes writes to the workspace, so a session running inside a repo
    # cannot append to ~/.claude/rules — measured: "operation not permitted",
    # which would leave the auto-update memory contract in AGENTS.md read-only in
    # practice. Grant that one directory as an extra writable root.
    #
    # ~/.codex/config.toml is Codex's OWN mutable state (auth mode, plugin
    # toggles, per-project trust), so this is a guarded append, not a managed
    # file: it never rewrites what is already there, and it says so loudly if a
    # [sandbox_workspace_write] table exists that it cannot safely extend. Same
    # shape as claudeStatuslineSettings merging settings.json.
    #
    # Create-once by design: it skips when `writable_roots` is already present, so
    # changing the intended root set here does NOT reach a machine that already ran
    # it — edit ~/.codex/config.toml on that machine, or drop the line first.
    # Verified that Codex preserves the table: `codex mcp add`/`remove` round-trips
    # config.toml surgically, leaving this block and its comments intact.
    home.activation.codexWritableRoots = (
      lib.hm.dag.entryAfter ["writeBoundary"] ''
        CFG="$HOME/.codex/config.toml"
        [ -e "$CFG" ] || : > "$CFG"
        if ${pkgs.gnugrep}/bin/grep -q 'writable_roots' "$CFG"; then
          :
        elif ${pkgs.gnugrep}/bin/grep -q '^\[sandbox_workspace_write\]' "$CFG"; then
          echo "codex: [sandbox_workspace_write] exists without writable_roots in $CFG; add $HOME/.claude/rules by hand or Codex cannot write its memory." >&2
        else
          printf '\n[sandbox_workspace_write]\n# Added by nix-config: lets a Codex session append to the shared memory\n# files in ~/.claude/rules (see ~/.codex/AGENTS.md).\nwritable_roots = ["%s/.claude/rules"]\n' "$HOME" >> "$CFG"
        fi
      ''
    );
  }
