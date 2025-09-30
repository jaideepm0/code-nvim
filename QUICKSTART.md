# Quick Start Guide - code-nvim

Get up and running with code-nvim in 5 minutes!

## Installation

### Using lazy.nvim

```lua
{
  "jaideepm0/code-nvim",
  config = function()
    require("vscode_style").setup()
  end,
}
```

### Using packer.nvim

```lua
use {
  "jaideepm0/code-nvim",
  config = function()
    require("vscode_style").setup()
  end,
}
```

### Manual

1. Clone the repository:
```bash
git clone https://github.com/jaideepm0/code-nvim ~/.local/share/nvim/site/pack/plugins/start/code-nvim
```

2. Add to your init.lua:
```lua
require("vscode_style").setup()
```

## Basic Usage

Once installed, you can use VSCode-style keybindings in **insert mode**:

### Selections
- `Shift + Left/Right` - Select characters
- `Shift + Up/Down` - Select lines
- `Ctrl + Shift + Left/Right` - Select words
- `Shift + Home/End` - Select to line start/end

### Multi-Cursor
- `Ctrl + D` - Add cursor at next match
- `Ctrl + Shift + L` - Add cursor at all matches
- `Ctrl + Alt + Up/Down` - Add cursor above/below
- `Alt + Click` - Add cursor at mouse position

### Line Operations
- `Alt + Up/Down` - Move line up/down
- `Shift + Alt + Up/Down` - Duplicate line
- `Ctrl + Shift + K` - Delete line

### Editing
- `Tab` - Indent selection
- `Shift + Tab` - Dedent selection
- `Backspace` - Delete selection
- Type to replace selection

## Simple Configuration Examples

### Example 1: Basic Setup
```lua
require("vscode_style").setup({
  -- Use default settings
})
```

### Example 2: Custom Highlight
```lua
require("vscode_style").setup({
  selection_hl = "Search",  -- Use Search highlight instead of Visual
  max_cursors = 64,         -- Allow more cursors
})
```

### Example 3: Disable for Markdown
```lua
require("vscode_style").setup({
  exclude_filetypes = { "markdown", "text" },
})
```

### Example 4: Customize Keybindings
```lua
require("vscode_style").setup({
  keymaps = {
    add_cursor_next_match = "<C-n>",  -- Use Ctrl+N instead of Ctrl+D
  },
})
```

### Example 5: Disable Multi-Cursor Feature
```lua
require("vscode_style").setup({
  features = {
    multi_cursor = false,  -- Disable multi-cursor
  },
})
```

### Example 6: Add Callbacks
```lua
require("vscode_style").setup({
  on_cursor_add = function(cursor)
    print("Cursor added at line " .. cursor.line)
  end,
})
```

## Common Use Cases

### Use Case 1: VSCode User Transitioning to Neovim
Perfect! Use default settings:
```lua
require("vscode_style").setup()
```

### Use Case 2: Want Selection but Not Multi-Cursor
```lua
require("vscode_style").setup({
  features = {
    selection = true,
    multi_cursor = false,
    line_manipulation = true,
  },
})
```

### Use Case 3: Only in Code Files
```lua
require("vscode_style").setup({
  include_filetypes = { "lua", "python", "javascript", "typescript" },
})
```

### Use Case 4: Respect My Existing Keybindings
```lua
require("vscode_style").setup({
  respect_existing_maps = true,  -- Won't override your mappings
})
```

### Use Case 5: Just Want to Try It Out
```lua
require("vscode_style").setup({
  buffer_local = true,  -- Enable per-buffer
})
```

Then in any buffer:
```vim
:lua require('vscode_style').enable()   " Enable for this buffer
:lua require('vscode_style').disable()  " Disable for this buffer
```

## Runtime Commands

```lua
-- Enable for current buffer
:lua require('vscode_style').enable()

-- Disable for current buffer
:lua require('vscode_style').disable()

-- Toggle on/off
:lua require('vscode_style').toggle()

-- Reload with new config
:lua require('vscode_style').reload({ debug = true })

-- Check current config
:lua vim.print(require('vscode_style').get_config())
```

## Troubleshooting

### Plugin not working?

1. **Check if initialized:**
```lua
:lua print(require('vscode_style').is_initialized())
```

2. **Enable debug mode:**
```lua
require("vscode_style").setup({ debug = true, log_level = "debug" })
```

3. **Check buffer status:**
```lua
:lua print(vim.b.vscode_style_enabled)
```

### Keybindings not working?

1. **Check if feature is enabled:**
```lua
:lua print(require('vscode_style').get_config().features.multi_cursor)
```

2. **Check for conflicts:**
```vim
:verbose imap <C-d>
```

3. **Try with respect_existing_maps:**
```lua
require("vscode_style").setup({ respect_existing_maps = false })
```

## Tips

1. **Use with mouse:** Set `set mouse=a` in your config
2. **ESC exits:** Press `<Esc>` to return to normal mode anytime
3. **Disable temporarily:** Use `:lua require('vscode_style').disable()`
4. **Check docs:** See `API.md` for complete reference

## Next Steps

- Read [README.md](./README.md) for complete documentation
- Check [API.md](./API.md) for full API reference
- See [CHANGELOG.md](./CHANGELOG.md) for version history
- Review [TODO.md](./TODO.md) for planned features

## Help

- GitHub Issues: https://github.com/jaideepm0/code-nvim/issues
- Documentation: See README.md and API.md
- Examples: Check the configuration examples above

## Quick Reference Card

```
Insert Mode Keybindings:

SELECTIONS:
  Shift + ←→↑↓         Select characters/lines
  Ctrl+Shift + ←→      Select words
  Shift + Home/End     Select to line boundary
  Ctrl+Shift+Home/End  Select to file boundary

MULTI-CURSOR:
  Ctrl + D             Next occurrence
  Ctrl + Shift + L     All occurrences
  Ctrl + Alt + ↑↓      Add cursor above/below
  Alt + Click          Add cursor at position

LINE OPERATIONS:
  Alt + ↑↓             Move line
  Shift + Alt + ↑↓     Duplicate line
  Ctrl + Shift + K     Delete line

EDITING:
  Tab                  Indent selection
  Shift + Tab          Dedent selection
  Backspace            Delete selection
  Type                 Replace selection
```

---

**Enjoy using code-nvim!** 🎉

For more information, see the full [README.md](./README.md)
