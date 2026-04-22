# Neovim Markdown Rendering

## Goal

Make reading markdown in neovim comfortable and efficient, both in-flow (inline styling while editing) and for polished review (browser preview).

## Scope

Two plugins added to the existing `programs.neovim-ide` configuration in `home/programs/neovim-ide/default.nix`. No changes to other modules.

## Components

### 1. Inline rendering — `render-markdown.nvim`

- **Source:** `pkgs.vimPlugins.render-markdown-nvim` (MeanderingProgrammer/render-markdown.nvim, packaged in nixpkgs).
- **How it's wired in:** Added to `vim.startPlugins` list alongside the existing entries (`agentic-nvim`, `nvim-highlight-colors`, `zellij-nav`).
- **Activation:** Auto-activates on markdown buffers via its own autocmds — no filetype plumbing needed from us.
- **Configuration:** `require("render-markdown").setup({})` in `luaConfigRC`. Start with defaults; can tune later.
- **Dependencies:** Needs treesitter parsers `markdown` and `markdown_inline`. Already provided because `vim.treesitter.enable = true` in the current config pulls all parsers.

### 2. Browser preview — `markdown-preview.nvim`

- **Source:** `pkgs.vimPlugins.markdown-preview-nvim` (iamcco/markdown-preview.nvim, packaged in nixpkgs — build step handled by the nixpkgs derivation).
- **How it's wired in:** Added to `vim.startPlugins`.
- **Activation:** On-demand via keymap. Opens live-updating rendered markdown in the user's default browser; closes automatically when the markdown buffer is left.
- **Configuration:** Defaults are fine. No setup call required.

### 3. Keymaps

Added to the existing `vim.nnoremap` table:

| Keymap       | Action                                  |
|--------------|-----------------------------------------|
| `<leader>mp` | `<cmd>MarkdownPreviewToggle<CR>`        |
| `<leader>mt` | `<cmd>RenderMarkdown toggle<CR>`        |

`<leader>mt` lets the user flip inline rendering off temporarily to see raw markdown — useful when editing character-level structure.

## Rollout

1. Edit `home/programs/neovim-ide/default.nix` with the additions above.
2. Run `./switch home` from the repo root.
3. Open any `.md` file to verify inline rendering; use `<leader>mp` to verify browser preview.

## Out of scope

- Swapping out the existing `markdown` section in `neovim-ide` settings (it stays `enable = false` — the new plugins are wired in via `startPlugins`/`luaConfigRC` rather than through that module's built-in markdown path).
- Themeing or deep customization of `render-markdown.nvim` — defaults first, tweak later if needed.
- Mermaid/LaTeX specifics — `markdown-preview.nvim` supports them out of the box; no extra config needed.
