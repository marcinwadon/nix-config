# Global instructions — Marcin

This is a **routing file**, not a knowledge dump. My durable rules and memory live
as Markdown in `~/.claude/rules/`. That directory is the single source of truth
for every assistant I use, Codex included — read it, and write back to it.

If a file listed here is missing, skip it silently.

## Read at the start of every session

Before your first substantive answer, read these six files (~20 KB total):

- `~/.claude/rules/memory-profile.md` — who I am, my role, my clients
- `~/.claude/rules/memory-preferences.md` — how I want you to behave
- `~/.claude/rules/memory-workflow.md` — when to ask vs. act, planning, git habits
- `~/.claude/rules/memory-tools.md` — package managers, CLIs, no global installs
- `~/.claude/rules/memory-systemic-mistakes.md` — the guardrail question to ask
- `~/.claude/rules/memory-lessons.md` — terse cross-project gotchas

Do this once per session, quietly, before answering. Do not summarise them back
to me unless I ask.

Then, also once and quietly, call `memory_recent` from the `memory` MCP server
for the current working directory. It returns what earlier sessions, Claude's
included, did and left pending in this repo. Claude Code gets the same brief
injected at session start; Codex has to ask for it. Use `memory_brief` or
`memory_search` later when a subject comes up that earlier sessions may have
covered. If the `memory` server is not available, skip this silently.

## Read on demand only

Never read these whole at session start — open or grep them only when the task
touches that project or a past decision:

- `~/.claude/projects/<repo>/memory/MEMORY.md` + the files it indexes — durable
  decisions and constraints for one repo (`<repo>` is the absolute repo path with
  every `/` and `_` replaced by `-`, e.g. `-Users-marcinwadon-Projects-marcinwadon-nix-config`)
- `~/.claude/archive/2026-09-26/memory-{decisions,sessions}.md` — the retired
  append-only logs (on older hosts they may still sit in `~/.claude/rules/`)

## Auto-update memory (MANDATORY)

Update these files **as you go**, not at the end. Do not ask permission — just write.

| Trigger | Action |
|---------|--------|
| I share a fact about myself | append to `memory-profile.md` |
| I state a preference | append to `memory-preferences.md` |
| A lesson that holds in EVERY repo | one terse line in `memory-lessons.md` |
| A decision in one project | record it in that repo's docs (spec/ADR), or tell me so Claude can file it in the project memory |
| Substantive work is completed | nothing — do NOT write session narratives anywhere in `~/.claude/rules/` |

These files are loaded into every Claude session and re-injected in full
whenever they change, so they must stay small: no project state, no stories.

Skip for quick factual questions and trivial tasks with no new information.

If the sandbox refuses the write, say so in your reply instead of dropping the
fact silently — an unrecorded memory is worse than a visible failure.

Claude Code reads and writes the same files, so anything you record here is
available there, and vice versa.

## Skills

My personal workflows live as skills in `~/.codex/skills/`. Prefer an existing
skill over improvising a workflow.
