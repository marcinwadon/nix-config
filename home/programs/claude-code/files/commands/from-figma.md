Implement a component or feature from a Figma design.

Figma URL: $ARGUMENTS

## Instructions

1. Extract fileKey and nodeId from the provided Figma URL

2. Fetch design context using the Figma MCP `get_design_context` tool

3. Analyze the existing codebase before writing any code:
   - Check ui-library for matching or similar components
   - Check the current app for existing patterns (layouts, spacing, tokens)
   - Identify reusable components that match parts of the design

4. Present the implementation plan:
   - Which existing components to reuse
   - What new components to create
   - Which design tokens / CSS variables to use
   - Any gaps between the design and available components

5. After approval, implement following project conventions:
   - Reuse ui-library and design system components
   - Use project's design tokens — do not hardcode colors or spacing
   - No type assertions (`as`) — use proper typing
   - Named exports only
   - Follow existing file/folder structure patterns

## Important
- Do NOT blindly copy the reference code from Figma — adapt it to the project's stack and conventions
- Always check for existing components first — avoid reimplementing what already exists
- If the design references components not in ui-library, flag it
- Ask before creating new shared components
