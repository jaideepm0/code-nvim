# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - 2024 - Production Release 🎉

### 🎯 Major Refactor - Non-Opinionated & Flexible

This release completely refactors the plugin to be **truly flexible and non-opinionated** as originally intended. All features, keybindings, and behaviors are now fully configurable.

### ✨ Added

#### Configuration System
- **Comprehensive configuration** with 30+ options
- **Feature toggles** - enable/disable specific features (selection, multi-cursor, line manipulation, column selection)
- **Keybinding control** - customize or disable any keybinding
- **Buffer-local configuration** - enable/disable per filetype/buffer
- **Namespace configuration** - avoid conflicts with other plugins

#### Extensibility
- **Callback system** - 6 lifecycle hooks (on_setup, on_cursor_add, on_cursor_remove, on_selection_change, on_enter_insert, on_leave_insert)
- **Custom actions** - add your own actions with custom keybindings
- **Action overrides** - override default action behavior
- **Respect existing mappings** - optionally don't override user's keymaps

#### API
- `enable()` - enable plugin for current buffer
- `disable()` - disable plugin for current buffer
- `toggle()` - toggle plugin on/off
- `reload(config)` - reload plugin with new configuration
- `get_config()` - get current configuration
- `get_state()` - get plugin state (debugging)
- `is_initialized()` - check if plugin is ready
- `get_cursor_count()` - get formatted cursor count for statusline

#### Documentation
- **API.md** - comprehensive API documentation with examples
- **Updated README.md** - complete configuration guide
- **Updated TODO.md** - tracked completed and planned features
- **CHANGELOG.md** - this file!

#### Code Quality
- **utils.lua** - shared utilities module
- **config.lua** - configuration management module
- **Error handling** - comprehensive pcall protection for all buffer operations
- **Logging system** - debug, info, warn, error levels
- **Type annotations** - LuaCATS style annotations throughout

#### Plugin Structure
- **plugin/ directory** - auto-loader for Neovim
- **lua/code-nvim.lua** - wrapper module (fixes documentation mismatch)
- **Modular architecture** - clean separation of concerns

### 🔧 Changed

#### Configuration
- **Breaking**: Configuration structure completely redesigned for flexibility
- **Breaking**: Default behavior now respects `enabled` flag
- Old configs with just `selection_hl` and `max_cursors` still work

#### Keybindings
- All keybindings now configurable via `keymaps` table
- Can disable specific keybindings without disabling feature
- Can customize keys for any action
- Mapping strategy now configurable (respect existing maps or override)

#### Code Organization
- Removed duplicate `buf()` function (now in utils)
- Split monolithic code into logical modules
- Better error messages and user feedback

### 🐛 Fixed

- **Documentation mismatch** - README said `require('code-nvim')` but only `require('vscode_style')` worked. Now both work!
- **Inconsistent mapping strategy** - some mappings respected existing, others didn't. Now configurable.
- **No error handling** - buffer operations could crash. Now all protected with pcall.
- **Hardcoded everything** - no flexibility. Now fully configurable.
- **No buffer-local control** - plugin was global. Now supports per-buffer/filetype configuration.

### 🚀 Performance

- Added safe buffer operations with error handling
- Optimized configuration merging
- Reduced redundant function calls

### 📚 Documentation

- Complete rewrite of README.md with examples
- New API.md with every function documented
- Updated TODO.md with completed items
- Added inline code documentation

---

## [1.0.0] - Previous Release

### Initial Implementation

#### Added
- Core VSCode-style keybindings in insert mode
- Multi-cursor editing
- Selection manipulation
- Line operations (move, copy, delete)
- Column/block selection
- Tab/Shift-Tab indentation
- Backspace deletion

#### Configuration
- `selection_hl` - highlight group
- `max_cursors` - cursor limit

---

## Migration Guide

### From 1.x to 2.0

#### Minimal Migration (No Changes Needed)

If you were using:
```lua
require('vscode_style').setup({
  selection_hl = 'Visual',
  max_cursors = 32,
})
```

This still works! No changes needed.

#### Module Name

Old (didn't work):
```lua
require('code-nvim').setup()  -- ❌ Error
```

New (both work):
```lua
require('vscode_style').setup()  -- ✅ Works
require('code-nvim').setup()     -- ✅ Works now!
```

#### Leveraging New Features

Take advantage of new configurability:

```lua
require('vscode_style').setup({
  -- Old config still works
  selection_hl = 'Visual',
  max_cursors = 32,
  
  -- NEW: Feature toggles
  features = {
    multi_cursor = true,      -- Enable
    line_manipulation = false, -- Disable
  },
  
  -- NEW: Disable specific keybindings
  disable_keymaps = { '<C-d>' },
  
  -- NEW: Customize keybindings
  keymaps = {
    add_cursor_next_match = '<C-n>',
  },
  
  -- NEW: Exclude filetypes
  exclude_filetypes = { 'markdown', 'text' },
  
  -- NEW: Callbacks
  on_cursor_add = function(cursor)
    print('Cursor added!')
  end,
})
```

#### Breaking Changes

None! Old configurations continue to work.

---

## Upgrade Checklist

- [ ] Update plugin with your package manager
- [ ] Read new README.md for configuration options
- [ ] Check API.md for new functions
- [ ] Consider using new features (callbacks, custom keybindings, etc.)
- [ ] Report any issues on GitHub

---

## Credits

Thanks to all contributors and users who provided feedback!

Special thanks to:
- Neovim team for the excellent Lua API
- VSCode team for the inspiration
- Plugin users for feature requests and bug reports

---

## Links

- [Repository](https://github.com/jaideepm0/code-nvim)
- [Issues](https://github.com/jaideepm0/code-nvim/issues)
- [API Documentation](./API.md)
- [README](./README.md)
