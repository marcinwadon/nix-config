Commit current changes, rebase with the up-to-date main branch, and push.

## Instructions

1. Run `git status` to see what's changed
2. If there are unstaged changes, stage and commit them with a descriptive message. Do not add description. If there is already a commit for this work, just ammend to have one commit per pull request.
3. If $ARGUMENTS is provided, use it as the commit message
4. If there's already a commit for the current work (i.e., no new changes but unpushed commits exist), skip creating a new commit
5. Determine the base branch:
   - Check if the PR already exists: `gh pr view --json baseRefName -q .baseRefName`
   - If no PR, default to `main`
6. Fetch and rebase: `git fetch origin && git rebase origin/<base-branch>`
7. If rebase conflicts occur, show them and ask for guidance — do NOT auto-resolve
8. Push: `git push` (or `git push -u origin HEAD` if no upstream is set)
9. If push is rejected because of rebase, ask before force-pushing
10. When commiting, use conventional commits. Use JIRA ticket number as a scope.

## Important
- Never use `--no-verify`
- Never force-push without asking first
- If there are no changes to commit and the branch is already up to date, say so
