Investigate Jira ticket $ARGUMENTS and prepare for implementation.

## Instructions

1. Fetch ticket details from Jira:
   - Get the ticket summary, description, acceptance criteria, and status
   - If it's a subtask, also fetch the parent ticket for full context
   - Check for linked tickets or blockers

2. Search the codebase for existing work:
   - Look for branches referencing the ticket ID: `git branch -a | grep -i $ARGUMENTS`
   - Search git log for commits: `git log --all --oneline --grep="$ARGUMENTS"`
   - Search for the ticket ID in code comments or TODOs

3. Analyze what already exists:
   - If there's a related branch, check what's been implemented
   - Search for feature flags associated with this ticket
   - Identify relevant components, services, or modules in the codebase

4. Summarize findings:
   - **Ticket**: title and key requirements
   - **Status**: what's already done vs what's remaining
   - **Relevant code**: key files and components involved
   - **Dependencies**: other tickets, libraries, or teams involved
   - **Feature flags**: any flags that gate this feature

5. Propose next steps and enter plan mode if implementation is needed

## Important
- Use Atlassian MCP tools for Jira access
- Read actual code before making assumptions about what exists
- If the ticket references Figma designs, note the links
