# VSCode Style Insert Editing for Neovim

`code-nvim` keeps you in insert mode while borrowing Visual Studio Code's core text-editing shortcuts. Hold familiar `Shift`, `Ctrl`, and `Alt` combinations to extend selections, jump to boundaries, and shuffle lines without leaving the flow of typing.

**Non-opinionated and flexible** - All features, keybindings, and behaviors are fully configurable.

## Features
- ✨ **Full VSCode-style editing in insert mode**
- 🎯 **Multi-cursor editing** with intelligent selection
- 🔧 **Fully configurable** - disable or customize any feature
- 📦 **Zero dependencies** - pure Lua implementation
- 🎨 **Buffer-local control** - enable/disable per filetype
- 🪝 **Extensible** - callbacks and custom actions support
- ⚡ **Production-ready** - comprehensive error handling

## Core Capabilities
- **Selections**: `Shift` + arrows, `Ctrl+Shift` + arrows for word selection
- **Boundaries**: `Shift+Home/End` for line, `Ctrl+Shift+Home/End` for file
- **Line Manipulation**: `Alt+Up/Down` to move, `Shift+Alt+Up/Down` to duplicate
- **Multi-cursor**: `Ctrl+D` for next match, `Ctrl+Shift+L` for all occurrences
- **Smart Editing**: Tab/Shift+Tab indent selection, Backspace deletes selection

## Installation

### With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "jaideepm0/code-nvim",
  config = function()
    require("vscode_style").setup({
      -- Core settings
      enabled = true,
      selection_hl = "Visual",
      max_cursors = 32,
      
      -- Features can be toggled
      features = {
        selection = true,
        multi_cursor = true,
        line_manipulation = true,
      },
      
      -- Exclude specific filetypes
      exclude_filetypes = { "help", "terminal" },
      
      -- See Configuration section for all options
    })
  end,
}
```

### Manual setup:

```lua
require("vscode_style").setup()
-- or
require("code-nvim").setup()  -- Both work!
```

## Configuration

### Basic Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | `boolean` | `true` | Master enable/disable |
| `selection_hl` | `string` | `"Visual"` | Highlight group for selections |
| `max_cursors` | `number` | `32` | Maximum concurrent cursors |
| `namespace` | `string` | `"vscode_style"` | Extmark namespace |

### Feature Toggles

```lua
features = {
  selection = true,         -- Shift+arrow selections
  multi_cursor = true,      -- Multi-cursor functionality
  line_manipulation = true, -- Alt+arrow line operations
  column_selection = true,  -- Column/block selection
}
```

### Keybinding Control

```lua
-- Disable default keymaps entirely
enable_default_keymaps = false,

-- Respect existing user mappings
respect_existing_maps = true,

-- Disable specific keymaps
disable_keymaps = { "<C-d>", "<C-S-l>" },

-- Customize individual keybindings
keymaps = {
  select_character_left = "<S-Left>",   -- Change key
  add_cursor_next_match = "<C-n>",      -- Remap
  select_all_occurrences = false,       -- Disable
},
```

### Buffer-Local Control

```lua
-- Enable per-buffer configuration
buffer_local = true,

-- Exclude specific filetypes
exclude_filetypes = { "help", "terminal", "qf" },

-- Or only include specific filetypes
include_filetypes = { "lua", "python", "javascript" },
```

### Callbacks and Extensibility

```lua
-- Hook into plugin lifecycle
on_setup = function()
  print("Plugin initialized!")
end,

on_cursor_add = function(cursor)
  -- Called when a cursor is added
end,

on_cursor_remove = function(cursor)
  -- Called when a cursor is removed
end,

on_selection_change = function(cursors)
  -- Called when selection changes
end,

on_enter_insert = function()
  -- Called when entering insert mode
end,

on_leave_insert = function()
  -- Called when leaving insert mode
end,

-- Add custom actions
actions = {
  my_custom_action = function()
    print("Custom action!")
  end,
},

-- Override default actions
action_overrides = {
  select_character = function(direction)
    -- Your custom selection logic
  end,
},
```

### Visual Feedback

```lua
-- Show cursor count in statusline
show_cursor_count = true,
cursor_count_format = "Cursors: %d",
cursor_count_hl = "Comment",
```

Then add to your statusline:
```lua
-- In your statusline config
require('vscode_style').get_cursor_count()
```

### Complete Example

```lua
require("vscode_style").setup({
  -- Core
  enabled = true,
  selection_hl = "Visual",
  max_cursors = 32,
  
  -- Buffer control
  exclude_filetypes = { "help", "terminal", "qf", "prompt" },
  
  -- Features
  features = {
    selection = true,
    multi_cursor = true,
    line_manipulation = true,
    column_selection = true,
  },
  
  -- Keybindings
  enable_default_keymaps = true,
  respect_existing_maps = false,
  
  -- Customize specific keybindings
  keymaps = {
    add_cursor_next_match = "<C-n>",  -- Change from <C-d>
    select_all_occurrences = "<C-A-l>",  -- Change from <C-S-l>
  },
  
  -- Disable specific keybindings
  disable_keymaps = {},
  
  -- Behavior
  backspace_deletes_selection = true,
  tab_indents_selection = true,
  typing_replaces_selection = true,
  
  -- Visual feedback
  show_cursor_count = false,
  
  -- Callbacks
  on_cursor_add = function(cursor)
    -- Custom logic
  end,
  
  -- Debug
  debug = false,
  log_level = "warn",  -- trace, debug, info, warn, error
})
```

## Runtime Commands

```lua
-- Enable/disable for current buffer
:lua require('vscode_style').enable()
:lua require('vscode_style').disable()
:lua require('vscode_style').toggle()

-- Reload configuration
:lua require('vscode_style').reload({ debug = true })

-- Get current config
:lua vim.print(require('vscode_style').get_config())
```

## Default Keybindings

All keybindings work in **insert mode only**:

### Selection
| Key | Action |
|-----|--------|
| `Shift + Left/Right` | Select character |
| `Shift + Up/Down` | Select line |
| `Ctrl + Shift + Left/Right` | Select word |
| `Shift + Home/End` | Select to line boundary |
| `Ctrl + Shift + Home/End` | Select to file boundary |

### Line Operations
| Key | Action |
|-----|--------|
| `Alt + Up/Down` | Move line up/down |
| `Shift + Alt + Up/Down` | Duplicate line up/down |
| `Ctrl + Shift + K` | Delete line |

### Multi-cursor
| Key | Action |
|-----|--------|
| `Ctrl + Alt + Up/Down` | Add cursor above/below |
| `Alt + Click` | Add cursor at position |
| `Ctrl + D` | Add cursor at next match |
| `Ctrl + Shift + L` | Add cursor at all matches |
| `Shift + Alt + Right/Left` | Expand/shrink selection |

### Editing
| Key | Action |
|-----|--------|
| `Tab` | Indent selection |
| `Shift + Tab` | Dedent selection |
| `Backspace` | Delete selection |

*All keybindings can be customized or disabled - see Configuration section.*

## Requirements
- Neovim 0.9 or newer
- No external dependencies

## Tips
- Use `set mouse=a` for column selection with mouse
- Press `<Esc>` to return to normal mode at any time
- Use `:lua require('vscode_style').disable()` to temporarily disable
- Check `:checkhealth vscode_style` for diagnostics (coming soon)

## Troubleshooting

### Plugin not working?
1. Check if enabled: `:lua vim.print(require('vscode_style').get_config().enabled)`
2. Check buffer-local setting: `:lua vim.print(vim.b.vscode_style_enabled)`
3. Enable debug mode: `require('vscode_style').setup({ debug = true, log_level = 'debug' })`
4. Check messages: `:messages`

### Keybindings not working?
1. Check if feature is enabled in `features` table
2. Verify keybinding not disabled in `disable_keymaps`
3. Check `respect_existing_maps` setting
4. Verify mapping: `:verbose imap <key>` (e.g., `:verbose imap <S-Left>`)

### Backspace not deleting selection?
This is a common issue. Here's how to fix it:

1. **Ensure feature is enabled:**
   ```lua
   require('vscode_style').setup({
     backspace_deletes_selection = true,  -- Must be true
   })
   ```

2. **Check if backspace is mapped:**
   ```vim
   :verbose imap <BS>
   ```
   Should show mapping to vscode_style handler

3. **Enable debug to see what's happening:**
   ```lua
   require('vscode_style').setup({
     backspace_deletes_selection = true,
     debug = true,
     log_level = 'debug',
   })
   ```
   Then press backspace and check `:messages`

4. **Verify selection exists:**
   - You should see visual highlight when text is selected
   - Try: Enter insert mode → Hold Shift → Press arrow keys
   - Selection should be highlighted

5. **Test with minimal config:**
   ```lua
   -- Disable other plugins temporarily
   require('vscode_style').setup({
     backspace_deletes_selection = true,
   })
   ```

6. **Check for conflicting plugins:**
   - Some plugins may override backspace behavior
   - Try disabling other insert-mode plugins temporarily

**Common causes:**
- Feature disabled in config (`backspace_deletes_selection = false`)
- Conflicting plugin overriding `<BS>` mapping
- Selection not properly established (no highlight visible)
- Not in insert mode when pressing backspace

**Still not working?** See [BACKSPACE_GUIDE.md](./BACKSPACE_GUIDE.md) for detailed debugging steps.

### Want to disable for specific files?
```lua
exclude_filetypes = { "markdown", "text" }
```

## License
MIT License - see LICENSE file for details

## Contributing
Contributions welcome! Please check existing issues or create a new one before submitting PRs.
