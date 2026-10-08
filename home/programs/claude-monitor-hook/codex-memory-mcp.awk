# Places exactly one [mcp_servers.memory] table in ~/.codex/config.toml.
#
#   awk -v url=<memory MCP url> -f codex-memory-mcp.awk config.toml
#
# Any existing memory table (and its sub-tables) is dropped and a fresh one is
# written directly ABOVE claude-monitor's managed block, or at the end when
# there is no block. Never at the top: a table header there would capture the
# root keys that follow it (model, approval_policy, ...).
#
# Not above-the-block for neatness: Codex appends new tables at EOF, i.e.
# inside the managed block, and the host rewrites that block wholesale on its
# next reconcile. Anything placed there (including `codex mcp add memory`)
# would be deleted.
#
# A line scanner, not a TOML parser. A line starting with "[" is a table header,
# which holds for everything Codex writes; a multi-line array whose continuation
# lines start with "[" would be misread.

BEGIN {
  marker = "# BEGIN claude-monitor mcp mounts"
  skip = 0
  done = 0
}

function emit(spacer) {
  print "[mcp_servers.memory]"
  print "# Managed by nix-config (claude-monitor-hook); rewritten on every activation."
  printf "url = \"%s\"\n", url
  # The memory tools carry no read-only annotation, so Codex's default mode
  # asks before every call; `codex exec` cannot ask and fails the call. The
  # server is our own and its tools only read or append session notes.
  print "default_tools_approval_mode = \"approve\""
  if (spacer) print ""
  done = 1
}

{
  # The marker is a comment, not a header, so it must also end a skipped table:
  # otherwise a memory table sitting right above the block would swallow it.
  if (index($0, marker) == 1) {
    skip = 0
    if (!done) emit(1)
    print
    blank = 0
    next
  }
  if ($0 ~ /^[ \t]*\[/) {
    h = $0
    gsub(/[ \t"']/, "", h)
    skip = (h ~ /^\[\[?mcp_servers\.memory[].]/)
    if (skip) next
  }
  if (skip) next
  print
  printed = 1
  blank = ($0 ~ /^[ \t]*$/)
}

END {
  # Separate from the previous table, but only once: a re-run must not grow
  # the blank-line run that is left behind where the old table was dropped.
  if (!done) {
    if (printed && !blank) print ""
    emit(0)
  }
}
