# Personal CLAUDE.md (global)

This file is a **routing file**, not a knowledge dump. It is loaded into every
session in every repo, and so is everything it `@`-imports — keep the imported
set small (target: under ~15 KB total). Paths resolve relative to `~/.claude/`.

## Loaded rules (always on)

@rules/memory-profile.md
@rules/memory-preferences.md
@rules/memory-workflow.md
@rules/memory-tools.md
@rules/memory-systemic-mistakes.md
@rules/memory-lessons.md

## Where memory lives

| Kind | Where | Loaded |
|------|-------|--------|
| Who I am, preferences, workflow, tools | `rules/memory-*.md` above | always |
| Cross-project gotchas that hold in EVERY repo | `rules/memory-lessons.md` | always |
| Durable decisions + constraints of one project | `~/.claude/projects/<repo>/memory/` (one fact per file + `MEMORY.md` index) | only in that repo |
| Session history ("what happened, what's pending") | memory MCP — written automatically per session | on demand: `memory_recent`, `memory_brief`, `memory_search` |
| Old decisions/sessions logs (until 2026-09-26) | `archive/2026-09-26/memory-{decisions,sessions}.md` (older hosts: left in `rules/`, no longer imported) | never — `grep` when needed |

## Auto-Update Memory (MANDATORY)

Update memory AS YOU GO, without asking — but into the right place:

| Trigger | Action |
|---------|--------|
| User shares a fact about themselves | → `rules/memory-profile.md` |
| User states a preference | → `rules/memory-preferences.md` |
| A decision is made in a project | → that project's `memory/` dir (or its spec in the repo). Date it. |
| A lesson that applies to EVERY repo | → one terse rule in `rules/memory-lessons.md` (no narrative) |
| Completing substantive work | → nothing to write: the memory MCP notes the session. Use `memory_remember` only when the operator says something worth keeping. |

**Never** append session narratives or per-project decisions to `~/.claude/rules/`.
Every change to an imported file is re-injected in full into live sessions, so
those files must stay small and change rarely.

**Skip:** quick factual questions, trivial tasks with no new info.
