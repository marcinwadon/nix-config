Review and address comments on PR #$ARGUMENTS.

## Instructions

1. Fetch all review comments and conversations:
   - `gh pr view $ARGUMENTS --json reviews,comments`
   - `gh api repos/{owner}/{repo}/pulls/$ARGUMENTS/comments`
   - `gh pr view $ARGUMENTS --comments`

2. Checkout the PR branch if not already on it:
   - `gh pr checkout $ARGUMENTS`

3. For each unresolved comment/suggestion:
   - Read the relevant file and surrounding context
   - Assess if the feedback is valid and actionable
   - Categorize: **address** (implement the fix) or **skip** (explain why)

4. Implement fixes for all "address" items

5. Present a summary:
   - What was addressed (with brief description of the change)
   - What was skipped and why
   - Any comments that need my input to decide

## Important
- Do NOT commit automatically — let me review the changes first
- Do NOT post replies to GitHub comments
- If a comment suggests an approach that conflicts with project conventions (CLAUDE.md), flag it
- When a comment is ambiguous, ask me instead of guessing
