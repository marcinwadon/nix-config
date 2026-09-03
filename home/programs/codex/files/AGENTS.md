# Global instructions — Marcin

This is a **routing file**, not a knowledge dump. My durable rules and memory live
as Markdown in `~/.claude/rules/`. That directory is the single source of truth
for every assistant I use, Codex included — read it, and write back to it.

If a file listed here is missing, skip it silently.

## Read at the start of every session

Before your first substantive answer, read these five files (~10 KB total):

- `~/.claude/rules/memory-profile.md` — who I am, my role, my clients
- `~/.claude/rules/memory-preferences.md` — how I want you to behave
- `~/.claude/rules/memory-workflow.md` — when to ask vs. act, planning, git habits
- `~/.claude/rules/memory-tools.md` — package managers, CLIs, no global installs
- `~/.claude/rules/memory-systemic-mistakes.md` — the guardrail question to ask

Do this once per session, quietly, before answering. Do not summarise them back
to me unless I ask.

## Read on demand only

These are large append-only logs. Do NOT read them whole at session start — grep
or tail them when the task actually touches a project, a past decision, or a
machine in my fleet:

- `~/.claude/rules/memory-decisions.md` (~80 KB) — architecture decision log
- `~/.claude/rules/memory-sessions.md` (~180 KB) — session log: current state,
  what is deployed, reusable gotchas per repo

## Auto-update memory (MANDATORY)

Update these files **as you go**, not at the end. Do not ask permission — just write.

| Trigger | Action |
|---------|--------|
| I share a fact about myself | append to `memory-profile.md` |
| I state a preference | append to `memory-preferences.md` |
| A decision is made | append to `memory-decisions.md` with the date |
| Substantive work is completed | append to `memory-sessions.md` |

Skip for quick factual questions and trivial tasks with no new information.

If the sandbox refuses the write, say so in your reply instead of dropping the
fact silently — an unrecorded memory is worse than a visible failure.

Claude Code reads and writes the same files, so anything you record here is
available there, and vice versa.

## Skills

My personal workflows live as skills in `~/.codex/skills/`. Prefer an existing
skill over improvising a workflow.
