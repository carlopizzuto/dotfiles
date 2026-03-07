# NVIM configuration

**Plugin Manager**: lazy.nivm

**init**
- imports **config.lazy**

### Config

**config.lazy**
- bootstraps lazy.nvim
- imorts **config.options**
- sets up lazy:
    - imports **plugins**
    - imports **plugins.colorscheme.{current}**
    
**config.options**
- central file for core vim options 

### Plugins

##### plugins.core
- **nvim-lua/plenary.nvim**
General‑purpose Lua helper library that many modern plugins rely on (no UI; just functions and async helpers).


- **folke/which-key.nvim**
Pop‑up hints for possible key‑bindings after you start a key sequence—great for discovering or remembering mappings.

- **nvim-telescope/telescope.nvim** 
Highly extensible fuzzy‑finder: search files, buffers, LSP symbols, git commits, etc., in an interactive floating window.
    
    - *(DEP)* **nvim-lua/plenary.nvim**
    See description above
    
- **polirritmico/telescope-lazy-plugins.nvim**
Telescope extension that lists your Lazy‑managed plugins with description, status and file path—handy for quick jumps.
    
    - *(DEP)* **nvim-telescope/telescope.nvim**
    Uses Telescope's picker interface to display plugins.

- **nvim-treesitter/nvim-treesitter**
Incremental Treesitter parsers for precise syntax highlighting, smart indentation, text objects and code navigation.

- **lewis6991/gitsigns.nvim**
Gutter signs showing added/changed/removed lines, inline blame, and easy staging/resetting of individual hunks.

##### plugins.coding
- smjonas/inc-rename.nvim:
    *(desc)*

- echasnovski/mini.bracketed
    *(desc)*

##### plugins.lsp
- neovim/nvim-lspconfig:
    *(desc)*

- williamboman/mason.nvim:
    *(desc)*

- williamboman/mason-lspconfig.nvim:
    *(desc)*

- hrsh7th/nvim-cmp:
    *(desc)*
    
    - (DEP) hrsh7th/cmp-nvim-lsp:
        *(desc)*
    
    - (DEP) L3MON4D3/LuaSnip:
        *(desc)*
