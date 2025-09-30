# API Documentation

## Module Loading

The plugin can be loaded using either module name:

```lua
local vscode_style = require('vscode_style')
-- or
local code_nvim = require('code-nvim')
```

Both provide the same API.

---

## Main API

### setup(config)

Initialize the plugin with optional configuration.

**Parameters:**
- `config` (table, optional): Configuration options (see Configuration section below)

**Returns:** None

**Example:**
```lua
require('vscode_style').setup({
  enabled = true,
  max_cursors = 32,
  features = {
    multi_cursor = true,
  },
})
```

---

### enable()

Enable the plugin for the current buffer.

**Parameters:** None

**Returns:** None

**Example:**
```lua
require('vscode_style').enable()
```

---

### disable()

Disable the plugin for the current buffer. Clears all selections and multi-cursors.

**Parameters:** None

**Returns:** None

**Example:**
```lua
require('vscode_style').disable()
```

---

### toggle()

Toggle the plugin on/off for the current buffer.

**Parameters:** None

**Returns:** None

**Example:**
```lua
require('vscode_style').toggle()
```

---

### reload(config)

Reload the plugin with new configuration. Clears existing state and re-initializes.

**Parameters:**
- `config` (table, optional): New configuration options

**Returns:** None

**Example:**
```lua
require('vscode_style').reload({ debug = true })
```

---

### get_config()

Get the current plugin configuration.

**Parameters:** None

**Returns:** 
- `table`: Current configuration

**Example:**
```lua
local config = require('vscode_style').get_config()
print(config.max_cursors)  -- 32
```

---

### get_state()

Get the current plugin state (for debugging).

**Parameters:** None

**Returns:**
- `table`: Internal plugin state including cursors, namespace, etc.

**Example:**
```lua
local state = require('vscode_style').get_state()
print(#state.cursors)  -- Number of active cursors
```

---

### is_initialized()

Check if the plugin has been initialized.

**Parameters:** None

**Returns:**
- `boolean`: `true` if initialized, `false` otherwise

**Example:**
```lua
if require('vscode_style').is_initialized() then
  print("Plugin is ready")
end
```

---

### get_cursor_count()

Get a formatted string with the current cursor count (for statusline integration).

**Parameters:** None

**Returns:**
- `string`: Formatted cursor count (empty if `show_cursor_count` is false or only 1 cursor)

**Example:**
```lua
-- In your statusline configuration
local cursor_count = require('vscode_style').get_cursor_count()
-- Returns: "Cursors: 3" when multiple cursors active
-- Returns: "" when single cursor or feature disabled
```

---

## Configuration Options

### Core Settings

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enabled` | boolean | `true` | Master enable/disable switch |
| `selection_hl` | string | `"Visual"` | Highlight group for selections |
| `max_cursors` | number | `32` | Maximum number of concurrent cursors |
| `namespace` | string | `"vscode_style"` | Extmark namespace (for avoiding conflicts) |

### Buffer-Local Settings

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `buffer_local` | boolean | `false` | Enable per-buffer configuration |
| `exclude_filetypes` | table | `{}` | List of filetypes to exclude |
| `include_filetypes` | table | `{}` | List of filetypes to include (empty = all) |

### Feature Toggles

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `features.selection` | boolean | `true` | Enable Shift+arrow selections |
| `features.multi_cursor` | boolean | `true` | Enable multi-cursor functionality |
| `features.line_manipulation` | boolean | `true` | Enable Alt+arrow line operations |
| `features.column_selection` | boolean | `true` | Enable column/block selection |

### Keybinding Control

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable_default_keymaps` | boolean | `true` | Enable all default keybindings |
| `respect_existing_maps` | boolean | `false` | Don't override existing user mappings |
| `disable_keymaps` | table | `{}` | List of keys to not map (e.g., `{"<C-d>"}`) |
| `keymaps` | table | `{}` | Custom keybinding overrides |

### Behavior Customization

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `backspace_deletes_selection` | boolean | `true` | Backspace deletes selected text |
| `tab_indents_selection` | boolean | `true` | Tab indents selected text |
| `typing_replaces_selection` | boolean | `true` | Typing replaces selected text |

### Visual Feedback

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `show_cursor_count` | boolean | `false` | Show cursor count in statusline |
| `cursor_count_format` | string | `"Cursors: %d"` | Format string for cursor count |
| `cursor_count_hl` | string | `"Comment"` | Highlight group for cursor count |

### Callbacks/Hooks

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `on_setup` | function | `nil` | Called after plugin setup |
| `on_cursor_add` | function | `nil` | Called when cursor is added |
| `on_cursor_remove` | function | `nil` | Called when cursor is removed |
| `on_selection_change` | function | `nil` | Called when selection changes |
| `on_enter_insert` | function | `nil` | Called when entering insert mode |
| `on_leave_insert` | function | `nil` | Called when leaving insert mode |

### Custom Actions

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `actions` | table | `{}` | Custom action functions |
| `action_overrides` | table | `{}` | Override default action behavior |

### Advanced/Debug

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `debug` | boolean | `false` | Enable debug mode |
| `log_level` | string | `"warn"` | Log level: trace, debug, info, warn, error |

---

## Keymap Action Names

Use these names in `keymaps` configuration to customize keybindings:

### Selection Actions
- `select_character_left` - Select character to the left
- `select_character_right` - Select character to the right
- `select_line_up` - Select line upward
- `select_line_down` - Select line downward
- `select_word_left` - Select word to the left
- `select_word_right` - Select word to the right
- `select_to_line_start` - Select to line start
- `select_to_line_end` - Select to line end
- `select_to_file_start` - Select to file start
- `select_to_file_end` - Select to file end

### Line Actions
- `move_line_up` - Move line up
- `move_line_down` - Move line down
- `copy_line_up` - Copy line up
- `copy_line_down` - Copy line down
- `delete_line` - Delete line

### Multi-Cursor Actions
- `alt_click` - Add cursor at mouse position
- `add_cursor_up` - Add cursor above
- `add_cursor_down` - Add cursor below
- `add_cursor_next_match` - Add cursor at next match
- `select_all_occurrences` - Select all occurrences
- `expand_selection` - Expand selection
- `shrink_selection` - Shrink selection

### Column Selection
- `column_selection_start` - Start column selection
- `column_selection_end` - End column selection

### Editing Actions
- `handle_tab` - Handle tab key
- `handle_shift_tab` - Handle shift+tab
- `handle_backspace` - Handle backspace
- `handle_backspace_ctrl` - Handle ctrl+backspace

---

## Callback Signatures

### on_setup()

Called after plugin setup completes.

```lua
on_setup = function()
  print("Plugin initialized!")
end
```

### on_cursor_add(cursor)

Called when a new cursor is added.

**Parameters:**
- `cursor` (table): Cursor object with `{ line, col, id, is_primary, ... }`

```lua
on_cursor_add = function(cursor)
  print(string.format("Cursor added at line %d, col %d", cursor.line, cursor.col))
end
```

### on_cursor_remove(cursor)

Called when a cursor is removed.

**Parameters:**
- `cursor` (table): Cursor object being removed

```lua
on_cursor_remove = function(cursor)
  print("Cursor removed")
end
```

### on_selection_change(cursors)

Called when any selection changes.

**Parameters:**
- `cursors` (table): Array of all cursor objects

```lua
on_selection_change = function(cursors)
  print(string.format("Selection changed, %d cursors active", #cursors))
end
```

### on_enter_insert()

Called when entering insert mode.

```lua
on_enter_insert = function()
  print("Entered insert mode")
end
```

### on_leave_insert()

Called when leaving insert mode.

```lua
on_leave_insert = function()
  print("Left insert mode")
end
```

---

## Custom Actions

You can define custom actions and map them to keys:

```lua
require('vscode_style').setup({
  actions = {
    my_custom_action = function()
      -- Your custom logic here
      print("Custom action executed!")
    end,
  },
  keymaps = {
    my_custom_action = '<C-S-a>',
  },
})
```

---

## Action Overrides

Override default action behavior:

```lua
require('vscode_style').setup({
  action_overrides = {
    select_character = function(direction)
      -- Your custom selection logic
      print("Custom select character: " .. direction)
      -- Call original if needed:
      -- require('vscode_style.actions').select_character_original(direction)
    end,
  },
})
```

---

## Buffer Variables

The plugin uses buffer-local variables:

- `vim.b.vscode_style_enabled` - Set to `true` or `false` to enable/disable per buffer

```lua
-- Disable for current buffer
vim.b.vscode_style_enabled = false

-- Enable for current buffer
vim.b.vscode_style_enabled = true
```

---

## Complete Configuration Example

```lua
require('vscode_style').setup({
  ----------------------------------------------------------------------------
  -- CORE SETTINGS
  ----------------------------------------------------------------------------
  enabled = true,
  selection_hl = 'Visual',
  max_cursors = 32,
  namespace = 'vscode_style',
  
  ----------------------------------------------------------------------------
  -- BUFFER-LOCAL SETTINGS
  ----------------------------------------------------------------------------
  buffer_local = false,
  exclude_filetypes = { 'help', 'terminal', 'qf', 'prompt' },
  include_filetypes = {},
  
  ----------------------------------------------------------------------------
  -- FEATURE TOGGLES
  ----------------------------------------------------------------------------
  features = {
    selection = true,
    multi_cursor = true,
    line_manipulation = true,
    column_selection = true,
  },
  
  ----------------------------------------------------------------------------
  -- KEYBINDING CONTROL
  ----------------------------------------------------------------------------
  enable_default_keymaps = true,
  respect_existing_maps = false,
  disable_keymaps = {},
  
  keymaps = {
    -- Customize specific keybindings
    add_cursor_next_match = '<C-n>',
    select_all_occurrences = '<C-A-l>',
    -- Disable specific actions
    -- expand_selection = false,
  },
  
  ----------------------------------------------------------------------------
  -- BEHAVIOR CUSTOMIZATION
  ----------------------------------------------------------------------------
  backspace_deletes_selection = true,
  tab_indents_selection = true,
  typing_replaces_selection = true,
  
  ----------------------------------------------------------------------------
  -- VISUAL FEEDBACK
  ----------------------------------------------------------------------------
  show_cursor_count = false,
  cursor_count_format = 'Cursors: %d',
  cursor_count_hl = 'Comment',
  
  ----------------------------------------------------------------------------
  -- CALLBACKS/HOOKS
  ----------------------------------------------------------------------------
  on_setup = function()
    vim.notify('VSCode-style plugin loaded!', vim.log.levels.INFO)
  end,
  
  on_cursor_add = function(cursor)
    -- Custom logic when cursor is added
  end,
  
  on_cursor_remove = function(cursor)
    -- Custom logic when cursor is removed
  end,
  
  on_selection_change = function(cursors)
    -- Custom logic on selection change
  end,
  
  on_enter_insert = function()
    -- Custom logic on insert mode entry
  end,
  
  on_leave_insert = function()
    -- Custom logic on insert mode exit
  end,
  
  ----------------------------------------------------------------------------
  -- CUSTOM ACTIONS
  ----------------------------------------------------------------------------
  actions = {
    my_action = function()
      print("Custom action!")
    end,
  },
  
  action_overrides = {
    -- Override default behavior
  },
  
  ----------------------------------------------------------------------------
  -- ADVANCED/DEBUG
  ----------------------------------------------------------------------------
  debug = false,
  log_level = 'warn',
})
```

---

## Integration Examples

### Statusline Integration (lualine)

```lua
require('lualine').setup({
  sections = {
    lualine_x = {
      function()
        return require('vscode_style').get_cursor_count()
      end,
    },
  },
})
```

### Statusline Integration (custom)

```lua
function StatusLine()
  local cursor_count = require('vscode_style').get_cursor_count()
  return cursor_count ~= '' and cursor_count or 'INSERT'
end
```

### Keybinding Integration

```lua
-- Add custom keybinding to toggle plugin
vim.keymap.set('n', '<leader>vt', function()
  require('vscode_style').toggle()
end, { desc = 'Toggle VSCode-style editing' })

-- Add keybinding to reload with debug
vim.keymap.set('n', '<leader>vr', function()
  require('vscode_style').reload({ debug = true, log_level = 'debug' })
end, { desc = 'Reload VSCode-style with debug' })
```

### Autocmd Integration

```lua
-- Automatically disable for specific file types
vim.api.nvim_create_autocmd('FileType', {
  pattern = { 'markdown', 'text' },
  callback = function()
    require('vscode_style').disable()
  end,
})
```

---

## Troubleshooting

### Getting Plugin Information

```lua
-- Check if plugin is initialized
:lua vim.print(require('vscode_style').is_initialized())

-- Get current configuration
:lua vim.print(require('vscode_style').get_config())

-- Get current state
:lua vim.print(require('vscode_style').get_state())

-- Check buffer-local setting
:lua vim.print(vim.b.vscode_style_enabled)
```

### Enable Debug Logging

```lua
require('vscode_style').reload({
  debug = true,
  log_level = 'debug',
})
```

### Check Keybindings

```lua
-- Check which keys are mapped in insert mode
:verbose imap <S-Left>
:verbose imap <C-d>
```

---

## Notes

- All keybindings are insert-mode only
- Plugin preserves buffer modified state during setup
- Selections are cleared automatically when leaving insert mode
- Multi-cursor state is preserved when re-entering insert mode
- All buffer operations are protected with error handling
- Callbacks are executed in protected mode (pcall)
