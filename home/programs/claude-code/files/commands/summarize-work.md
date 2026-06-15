Summarize the recent work on the current branch.

## Instructions

1. Determine the base branch (same logic as /ship — check PR or default to main/develop)

2. Gather all changes since diverging from base:
   - `git log <base>..HEAD --oneline` for commit list
   - `git diff <base>..HEAD --stat` for files changed overview

3. For each commit, provide a 1-2 sentence summary of the change

4. Write an overall summary covering:
   - What was implemented/fixed
   - Key decisions made
   - Any caveats or follow-ups needed

## Output Format

Adapt format based on $ARGUMENTS:

- **"pr"** — Format as a PR description with ## Summary, ## Changes, ## Test Plan sections
- **"slack"** — Format as a concise Slack message with bullet points, suitable for posting in a channel
- **"pl"** or **"polish"** — Write the summary in Polish language
- **No argument** — Default to a clean markdown summary

## Important
- Focus on the "why" not just the "what"
- Keep it concise — no one reads walls of text
- If there are no commits beyond the base branch, say so
