{ config, lib, pkgs, ... }:

let
  metals = pkgs.callPackage ./metals.nix { };

  openaiApiKey = import ../../secrets/openaiApiKey;
in
{
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
          vim-surround
        ];
        neovim.package = pkgs.neovim-nightly;
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
            inherit metals;
            enable = true;
          };
          ts = true;
          smithy = true;
          go = true;
        };
        plantuml.enable = true;
        visuals = {
          enable = true;
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
        autocomplete = {
          enable = true;
          type = "nvim-cmp";
        };
        filetree.nvimTreeLua = {
          enable = true;
          hideDotFiles = false;
          hideFiles = [ "node_modules" ".cache" ];
          openOnSetup = false;
        };
        neoclip.enable = true;
        hop.enable = true;
        notifications.enable = true;
        todo.enable = true;
        tabline.nvimBufferline.enable = true;
        treesitter = {
          enable = true;
          autotagHtml = true;
          context.enable = true;
        };
        scala = {
          highlightMode = "treesitter";
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
        telescope = {
          enable = true;
        };
        markdown = {
          enable = true;
          glow.enable = true;
        };
        git = {
          enable = true;
          gitsigns.enable = true;
        };
        spider = {
          enable = true;
          skipInsignificantPunctuation = true;
        };
        chatgpt = {
          enable = true;
          inherit openaiApiKey;
        };
        nnoremap = {
          "<leader>mc" = "<cmd>lua require('telescope').extensions.metals.commands()<CR>";
          "<leader><leader>o" = "<cmd>lua require('metals').organize_imports()<CR>";
        };
      };
    };
  };
}
