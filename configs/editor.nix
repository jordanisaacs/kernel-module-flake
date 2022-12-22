{
  writeShellScript,
  enableRust,
}: {...}: {
  config = {
    vim.lsp = {
      enable = true;
      lightbulb.enable = true;
      lspSignature.enable = true;
      trouble.enable = true;
      nvimCodeActionMenu.enable = true;
      formatOnSave = true;
      clang = {
        enable = true;
        c_header = true;
      };
      rust = {
        enable = enableRust;
        rustAnalyzerOpts = let
          cmd =
            writeShellScript
            "module-ra-check"
            ''make -s "KRUSTFLAGS+=--error-format=json" 2>&1 | grep -v "^make"'';
        in ''
          ["rust-analyzer"] = {
            cargo = {
              buildScripts = {
                overrideCommand = {"${cmd}"},
              },
            },
            checkOnSave = {
              overrideCommand = {"${cmd}"},
            },
          },
        '';
      };
      nix.enable = true;
    };
    vim.statusline.lualine = {
      enable = true;
      theme = "onedark";
    };
    vim.visuals = {
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
    vim.theme = {
      enable = true;
      name = "onedark";
      style = "darker";
    };
    vim.autopairs.enable = true;
    vim.autocomplete = {
      enable = true;
      type = "nvim-cmp";
    };
    vim.filetree.nvimTreeLua.enable = true;
    vim.tabline.nvimBufferline.enable = true;
    vim.telescope = {
      enable = true;
    };
    vim.markdown = {
      enable = true;
      glow.enable = true;
    };
    vim.treesitter = {
      enable = true;
      context.enable = true;
    };
    vim.keys = {
      enable = true;
      whichKey.enable = true;
    };
    vim.git = {
      enable = true;
      gitsigns.enable = true;
    };
    vim.tabWidth = 8;
  };
}
