{ config
, lib
, pkgs
, ...
}:
let
  metals = pkgs.callPackage ./metals.nix { };

  openaiApiKey = import ../../secrets/openaiApiKey;

  agentic-nvim = pkgs.vimUtils.buildVimPlugin {
    pname = "agentic-nvim";
    version = "2026-01-27";
    src = pkgs.fetchFromGitHub {
      owner = "carlos-algms";
      repo = "agentic.nvim";
      rev = "e70d26a66821fe44f5c1b38896e59a955f6dd09a";
      hash = "sha256-8OAiP50gYNiUXt+HTkunR9J5MYhUxDs5JBN+Q7TAD+A=";
    };
    nvimRequireCheck = "agentic";
  };

  nvim-highlight-colors = pkgs.vimUtils.buildVimPlugin {
    pname = "nvim-highlight-colors";
    version = "2025-09-06";
    src = pkgs.fetchFromGitHub {
      owner = "brenoprata10";
      repo = "nvim-highlight-colors";
      rev = "e0c4a58ec8c3ca7c92d3ee4eb3bc1dd0f7be317e";
      hash = "sha256-BIcOU2Gie90wujQFZ+aD3wYTRegSKw4CBxC95DRwo9I=";
    };
    nvimRequireCheck = "nvim-highlight-colors";
    nvimSkipModule = [
      "nvim-highlight-colors.color.patterns_spec"
      "nvim-highlight-colors.color.converters_spec"
      "nvim-highlight-colors.color.utils_spec"
      "nvim-highlight-colors.buffer_utils_spec"
      "nvim-highlight-colors.utils_spec"
    ];
  };
in
{
  home.packages = [ pkgs.claude-code-acp ];

  programs.neovim-ide = {
    enable = true;
    settings = {
      vim = {
        viAlias = false;
        vimAlias = true;
        #disableArrows = false;
        lineNumberMode = "number";
        mapLeaderSpace = false;
        preventJunkFiles = true;
        customPlugins = with pkgs.vimPlugins; [
          multiple-cursors
          vim-mergetool
          vim-repeat
          conform-nvim
        ];
        startPlugins = [ agentic-nvim nvim-highlight-colors ];
        luaConfigRC = ''
          require("agentic").setup({
            provider = "claude-acp",
          })

          -- nvim-highlight-colors: show actual colors inline for hex/rgb values
          require("nvim-highlight-colors").setup({
            render = "background", -- or "foreground" or "virtual"
            enable_named_colors = true,
            enable_tailwind = true,
          })

          -- conform.nvim: lightweight formatting
          require("conform").setup({
            formatters_by_ft = {
              javascript = { "prettier" },
              typescript = { "prettier" },
              typescriptreact = { "prettier" },
              javascriptreact = { "prettier" },
              json = { "prettier" },
              yaml = { "prettier" },
              html = { "prettier" },
              css = { "prettier" },
              markdown = { "prettier" },
              python = { "isort", "black" },
              nix = { "alejandra" },
              go = { "gofmt" },
              rust = { "rustfmt" },
            },
            -- Set up format-on-save (optional, disabled by default to match your LSP setting)
            -- format_on_save = {
            --   timeout_ms = 500,
            --   lsp_fallback = true,
            -- },
          })
          -- Keymap for manual formatting with conform
          vim.keymap.set({ "n", "v" }, "<leader>cf", function()
            require("conform").format({ async = true, lsp_fallback = true })
          end, { desc = "Format buffer (conform)" })

          -- Set Visual highlight (visible blue)
          local function set_visual_hl()
            vim.api.nvim_set_hl(0, "Visual", { bg = "#3d59a1" })
          end
          vim.api.nvim_create_autocmd({"VimEnter", "ColorScheme"}, {
            callback = function()
              vim.schedule(set_visual_hl)
            end,
          })
          set_visual_hl()
        '';
        # neovim.package = pkgs.neovim;
        lsp = {
          enable = true;
          folds = true;
          formatOnSave = false;
          lightbulb.enable = true;
          lspsaga.enable = false;
          nvimCodeActionMenu.enable = true;
          trouble.enable = true;
          lspSignature.enable = true;
          nix = {
            enable = true;
            type = "nil";
          };
          scala = {
            enable = true;
          };
          ts = true;
          smithy.enable = true;
          go = true;
          rust.enable = true;
          #python = true;
        };
        plantuml.enable = true;
        visuals = {
          enable = true;
          modes.enable = false;  # disable modes.nvim - it interferes with Visual highlight
          noice.enable = true;
          nvimWebDevicons.enable = true;
          lspkind.enable = true;
          indentBlankline = {
            enable = true;
            fillChar = "";
            eolChar = "";
            showCurrContext = true;
          };
          cursorWordline = {
            enable = true;
            lineTimeout = 0;
          };
        };
        statusline.lualine = {
          enable = true;
          theme = "onedark";
        };
        theme = {
          enable = true;
          name = "onedark";
          style = "deep";
          transparency = false;
        };
        autopairs.enable = true;
        autocomplete.enable = true;
        filetree.nvimTreeLua = {
          enable = true;
          hideDotFiles = false;
          hideFiles = [ "node_modules" ".cache" ".DS_Store" ];
          openOnSetup = false;
        };
        neoclip.enable = true;
        dial.enable = true;
        harpoon.enable = true;
        hop.enable = true;
        notifications.enable = true;
        snippets.vsnip.enable = true;
        snacks.enable = true;
        tide = {
          enable = true;
          keys.splits.vertical = "~";
        };
        todo.enable = true;
        tabline.nvimBufferline.enable = true;
        zen.enable = true;
        treesitter = {
          enable = true;
          autotagHtml = true;
          context.enable = true;
        };
        keys = {
          enable = true;
          whichKey.enable = true;
        };
        comments = {
          enable = true;
          type = "nerdcommenter";
        };
        shortcuts = {
          enable = true;
        };
        surround = {
          enable = true;
        };
        telescope = {
          enable = true;
          tabs.enable = true;
        };
        markdown = {
          enable = false;
          glow.enable = false;
        };
        git = {
          enable = true;
          gitsigns.enable = true;
          neogit.enable = true;
        };
        spider = {
          enable = true;
          skipInsignificantPunctuation = true;
        };
        chatgpt = {
          enable = false;
        };
        nnoremap = {
          "<leader>fr" = "<cmd>Telescope resume<CR>";
          "<leader>mc" = "<cmd>lua require('telescope').extensions.metals.commands()<CR>";
          "<leader><leader>o" = "<cmd>lua require('metals').organize_imports()<CR>";
          "<leader><leader>f" = "<cmd>!prettier -w %<CR>";
          "<leader><leader>i" = "<cmd>!black %<CR>";
          "<leader><leader>u" = "<cmd>!isort %<CR>";
          "<leader><leader>y" = "<cmd>!autoflake -r --in-place --remove-unused-variables %<CR>";
          # agentic.nvim keymaps
          "<C-\\>" = "<cmd>lua require('agentic').toggle()<CR>";
          "<C-'>" = "<cmd>lua require('agentic').add_selection_or_file_to_context()<CR>";
        };
      };
    };
  };
}
