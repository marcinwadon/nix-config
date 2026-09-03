---
name: fix-dependabot-alerts
description: Use when asked to analyze, triage, or fix a repository's open Dependabot security alerts / vulnerability alerts — bumping direct and transitive dependencies via the repo's override/resolution mechanism and opening a remediation PR.
---

# Fix Dependabot Alerts

## Overview

Remediate a repo's open Dependabot alerts by upgrading each vulnerable package
(direct or transitive) to a patched version, using the repo's EXISTING
pin/override mechanism. Verify against the actual lockfile — CI-green is not proof
the vulnerable version is gone.

**Core principle: the lockfile is the source of truth.** Confirm no instance of
any alerted package remains in a vulnerable range — not merely that a patched one
appeared (multiple versions coexist; partial fixes are easy to miss).

Start by gathering + grouping the alerts, then SHOW THE PLAN (package → fix →
mechanism) before applying — the direct-vs-transitive and keyed-vs-blanket
decisions are where mistakes happen.

## When to Use

- "Fix the Dependabot alerts", "clear the security alerts", "bump the vulnerable deps".
- A repo's Security tab shows open vulnerability alerts.
- Not for: general dependency upgrades unrelated to security (use normal upgrade flow).

## 1. Gather

```bash
gh api /repos/<owner>/<repo>/dependabot/alerts --paginate \
  | jq -r '[.[]|select(.state=="open")]
    | group_by(.security_vulnerability.package.name)[]
    | {pkg:.[0].security_vulnerability.package.name, count:length,
       manifests:(map(.dependency.manifest_path)|unique)}'
```

For each alert capture: package, ecosystem, severity, `vulnerable_version_range`,
`first_patched_version`, `dependency.scope`, and `manifest_path`
(**package.json = direct/declared**, **lockfile = transitive-only**).

Detect the package manager and the repo's EXISTING remediation pattern before
inventing one: pnpm `pnpm.overrides` + `catalog:`, npm `overrides`, yarn
`resolutions`. Follow the repo's convention.

## 2. Plan (the decisions that bite)

| Situation | Do |
|---|---|
| Direct dep (declared in a package.json) | Bump the declared version to the patched version |
| Transitive-only (lockfile alert) | Pin via the repo's override/resolution mechanism |
| A package appears BOTH as catalog citizen AND transitively | Catalog/declared bump alone won't move the transitive copy — add an override too |
| Floor version | Pin to the EXACT version that resolves, not minimum-to-patch (see below) |
| Newer MAJOR of the package exists on the registry | Use a KEYED/scoped range override so you don't force a transitive consumer across a major |
| Repo has a release-age quarantine | Confirm each patched version is old enough, or the install refuses it |

**Exact-version pins:** a floor like `>=8.6.0` installs the latest aged match
(e.g. `8.6.5`), so package.json would show a different number than the lockfile
and look like a bug on review. After install, grep the lockfile for what actually
resolved and set the floor to that exact number (keep the repo's operator style).

**Keyed ranges:** check `npm view <pkg> version` for a newer major. If one exists,
scope the override to the vulnerable range only, e.g.
`"http-proxy-middleware@>=0.16.0 <2.0.10": "2.0.10"` — NOT a blanket `>=2.0.10`
(which resolves to the newest satisfying version = a major jump). Blanket floors
are fine only when no newer major exists. Don't clobber a keyed override that
surgically excludes another major.

**Release-age quarantine (pnpm `minimumReleaseAge`, `trustPolicy`):** verify each
patched version predates the window with `npm view <pkg>@<ver> time`; if too new,
the install won't select it.

## 3. Apply + regenerate lockfile

- Make the edits, then regenerate the lockfile.
  - pnpm catalog/override bumps: `pnpm install --lockfile-only --fix-lockfile --no-frozen-lockfile` (plain install no-ops on catalog changes).
- **pnpm ONLY — always `pnpm dedupe` after any lockfile change**, then
  `pnpm dedupe --check` (expect exit 0). `--fix-lockfile` tends to introduce
  duplicate transitive trees (hasown, webpack, `@types/node`, `@babel/*`) that
  CI's dedupe gate rejects.

## 4. Verify (lockfile, not just CI)

- Re-grep the lockfile for EVERY alerted package; confirm no instance remains in a
  vulnerable range:
  ```bash
  grep -oE "'?<pkg>@[0-9][^:'\"()]*" <lockfile> | sort -uV
  ```
- Frozen install passes (lockfile complete/consistent): `pnpm install --frozen-lockfile`.
- Typecheck + a production build on ≥1 workspace consuming the bumped build-critical
  deps (babel/webpack/etc.) — dep bumps break at build time, not lint time.
- Run the repo's mandatory validation (format/lint/typecheck) on changed files.

## 5. Commit + PR

- One batched commit is fine for a security sweep.
- Use the repo's commit convention. If it requires a ticket in the scope, ASK for
  the ticket number before committing — don't invent one.
- PR body: a table (package / was / now / mechanism) + the verification results.
- Disclose AI authorship per any org policy footer requirement.

## 6. After merge

- Dependabot closes **package.json-manifest** alerts quickly but re-evaluates
  **lockfile (transitive)** alerts on a slower cadence — often hours. If the
  lockfile is verifiably clean, remaining lockfile alerts are re-scan lag and will
  auto-close. DON'T manually dismiss them (auto-close records "Fixed" — a clean
  audit trail).

## Common Mistakes

- **Trusting CI-green over the lockfile.** A partial fix (one patched instance +
  one lingering vulnerable instance) passes build but leaves the alert open.
- **Blanket `>=` override crossing a major** (e.g. forcing v2 consumers onto v4).
- **Catalog/declared bump without an override** for a package that's also pulled
  transitively — the transitive copy stays vulnerable and the alert survives.
- **The pnpm `dedupe --check` gate is nondeterministic in the merge queue.** It
  re-resolves against the LIVE registry under the age gate, so a merge-queue run
  can flag a dedupe a passing PR run didn't — same OS, same lockfile. Handling:
  don't chase a local repro; rebase onto latest main, re-verify, re-queue ONCE
  (versions only age forward). A second identical flake → suspect a stale local
  pnpm metadata cache (CI resolves fresh): refresh metadata, re-run `pnpm dedupe`,
  commit. Consider flagging the flaky gate as a systemic issue to the team.
