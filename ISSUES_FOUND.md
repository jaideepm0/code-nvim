# Issues Found in code-nvim Plugin

**Analysis Date:** Generated on request  
**Requirement:** Plugin should be "non-opinionated but very flexible alongside being extremely useful"

---

## 🔴 Critical Issues (Must Fix)

### 1. Lack of Configurability - Violates "Non-Opinionated" Requirement
**Severity:** CRITICAL  
**Files:** `lua/vscode_style/init.lua`

The plugin only exposes 2 configuration options:
- `selection_hl` - Highlight group
- `max_cursors` - Maximum cursor count

**Problems:**
- ❌ All 26+ keybindings are hardcoded with no disable option
- ❌ Cannot customize which keys trigger which actions
- ❌ No feature toggles (can't disable multi-cursor, line manipulation, etc.)
- ❌ No callback/hook system for extensibility
- ❌ No buffer-local configuration (can't enable/disable per filetype)

**Impact:** Plugin is highly opinionated and inflexible, directly violating the stated requirement.

**Required Changes:**
```lua
-- Need to support configuration like:
require('vscode_style').setup({
  enabled = true,
  enable_default_keymaps = true,
  disable_keymaps = { '<C-d>', '<C-S-l>' },  -- Disable specific bindings
  keymaps = {
    select_character_left = '<S-Left>',  -- Customize keys
    add_cursor_next = false,  -- Or disable entirely
  },
  features = {
    multi_cursor = true,
    line_manipulation = true,
    selection = true,
  },
  exclude_filetypes = { 'help', 'terminal' },
  on_cursor_add = function(cursor) end,  -- Hooks for extensibility
})
```

---

### 2. Documentation Inconsistency - Module Name Mismatch
**Severity:** HIGH  
**File:** `README.md:33`

**Problem:**
```markdown
`setup()` is optional—`require("code-nvim")` bootstraps the defaults automatically
```

But the actual module is `vscode_style`, not `code-nvim`. Users following docs will get:
```
E5113: Error while calling lua chunk: module 'code-nvim' not found
```

**Fix Options:**
1. Update README to use `require("vscode_style")` everywhere, OR
2. Create `lua/code-nvim.lua` wrapper that requires vscode_style

---

### 3. No Buffer-Local Configuration
**Severity:** HIGH  
**File:** `lua/vscode_style/init.lua`

**Problem:** Plugin applies globally to all buffers with no way to:
- Enable/disable per filetype
- Use different settings for different buffer types
- Disable in terminal, quickfix, help, etc.

**Use Case:** User wants VSCode-style editing in code files but not markdown or help files.

**Required:** Add filetype-aware configuration and buffer-local enable/disable.

---

## 🟡 High Priority Issues

### 4. Duplicate Code - `buf()` Function
**Severity:** MEDIUM  
**Files:** `lua/vscode_style/actions.lua:6` and `lua/vscode_style/multi_cursor.lua:19`

Both files define identical local `buf()` function:
```lua
local function buf()
  return vim.api.nvim_get_current_buf()
end
```

**Fix:** Extract to shared utility module: `lua/vscode_style/utils.lua`

---

### 5. Inconsistent Mapping Strategy
**Severity:** MEDIUM  
**File:** `lua/vscode_style/init.lua:80-89`

**Problem:**
- Backspace and Ctrl+h use `map_if_unmapped` (respects existing mappings)
- All other 24+ keybindings use `map` (overwrites existing mappings)

**Impact:** Plugin inconsistently overrides user mappings, unexpected behavior.

**Fix:** 
1. Use `map_if_unmapped` for ALL mappings, OR
2. Make it configurable via `respect_existing_maps` option

---

### 6. Limited Error Handling
**Severity:** MEDIUM  
**File:** `lua/vscode_style/actions.lua`

**Finding:** 0 `pcall` usages in 1100+ lines of buffer manipulation code.

Many operations can fail but aren't protected:
```lua
-- Current (unsafe):
vim.api.nvim_buf_set_lines(buf(), start, end_line + 1, false, {})

-- Should be (safe):
local ok, err = pcall(vim.api.nvim_buf_set_lines, buf(), start, end_line + 1, false, {})
if not ok then
  vim.notify('Failed: ' .. tostring(err), vim.log.levels.ERROR)
  return
end
```

**Required:** Add proper error handling to all buffer/extmark operations.

---

### 7. No Plugin Auto-Load Structure
**Severity:** MEDIUM  
**Location:** Root directory

**Missing:** Standard Neovim plugin structure lacks `plugin/` directory.

**Current:** Users must manually call `require('vscode_style').setup()`

**Should Have:**
```
plugin/
  └── code-nvim.lua  -- Auto-loaded by Neovim
```

This would allow zero-configuration usage with sensible defaults.

---

### 8. No Support for Custom Actions
**Severity:** HIGH (for flexibility requirement)  
**File:** `lua/vscode_style/init.lua`

Users cannot:
- Add custom actions
- Override existing action behavior
- Hook into action lifecycle

**Required for flexibility:**
```lua
{
  actions = {
    my_custom_action = function() ... end,
  },
  action_overrides = {
    select_character = function(direction) ... end,
  },
}
```

---

## 🟢 Medium Priority Issues

### 9. Missing Status Indicator
**Severity:** LOW (but in TODO.md)  
**File:** N/A

From TODO.md:
> Expose a status indicator showing how many insert-mode cursors are active

**Should support:**
```lua
{
  show_cursor_count = true,
  cursor_count_format = 'Cursors: %d',
  cursor_count_position = 'statusline',  -- or 'virtual_text'
}
```

---

### 10. No Automated Tests
**Severity:** HIGH  
**Location:** `tests/` directory

**Current state:**
- `tests/tests.md` - Manual test checklist only
- `tests/main.py` - Unrelated Python code
- No Lua tests (busted/plenary)
- No CI/CD

From TODO.md:
> Add retry-safe automated tests (busted or plenary)

**Impact:** No regression testing, risky to refactor or add features.

---

### 11. Incomplete Documentation
**Severity:** MEDIUM  
**File:** `README.md`

**Missing:**
- Configuration options beyond the 2 documented
- Troubleshooting section (mentioned in TODO)
- API documentation for advanced usage
- Examples of common configurations
- How to disable specific features
- Integration with other plugins

---

### 12. No Undo/Redo Documentation
**Severity:** MEDIUM  
**File:** Documentation

**Unclear:**
- Are multi-cursor edits atomic (single undo point)?
- Or does each cursor create separate undo points?
- How does undo/redo interact with selections?

**Required:** Document undo behavior explicitly.

---

### 13. Hardcoded Namespace
**Severity:** LOW  
**File:** `lua/vscode_style/init.lua:145`

```lua
state.ns = vim.api.nvim_create_namespace('vscode_style')
```

**Should be configurable** to avoid conflicts:
```lua
{ namespace = 'vscode_style' }
```

---

### 14. No Cleanup/Disable Mechanism
**Severity:** LOW  
**File:** `lua/vscode_style/init.lua`

Plugin creates autocmds but no way to:
- Disable plugin at runtime
- Reload configuration
- Clean up resources
- Temporarily toggle plugin on/off

---

## 📋 Feature Completeness Checklist

According to AGENTS.md requirements:

| Feature | Status | Notes |
|---------|--------|-------|
| Core selection (Shift+arrows) | ✅ Implemented | Works |
| Word selection (Ctrl+Shift+arrows) | ✅ Implemented | Works |
| Line selection (Shift+Up/Down) | ✅ Implemented | Works |
| File boundary selection | ✅ Implemented | Works |
| Line manipulation (Alt+arrows) | ✅ Implemented | Works |
| Line duplication (Shift+Alt+arrows) | ✅ Implemented | Works |
| Delete line (Ctrl+Shift+K) | ✅ Implemented | Works |
| Multi-cursor (Ctrl+Alt+arrows) | ✅ Implemented | Works |
| Add cursor (Alt+Click) | ✅ Implemented | Works |
| Next match (Ctrl+D) | ✅ Implemented | Works |
| All occurrences (Ctrl+Shift+L) | ✅ Implemented | Works |
| Expand/shrink selection | ⚠️ Partial | Basic implementation |
| Column selection (mouse drag) | ⚠️ Partial | Mouse only |
| **Configurability** | ❌ Missing | **Critical** |
| **Buffer-local settings** | ❌ Missing | **High Priority** |
| **Custom keybindings** | ❌ Missing | **Critical** |
| **Feature toggles** | ❌ Missing | **Critical** |
| **Hooks/callbacks** | ❌ Missing | **High Priority** |

---

## 💡 Recommended Configuration Schema

To meet "non-opinionated and flexible" requirement:

```lua
require('vscode_style').setup({
  ----------------------------------------------------------------------------
  -- CORE SETTINGS
  ----------------------------------------------------------------------------
  enabled = true,                    -- Master enable/disable
  selection_hl = 'Visual',           -- Highlight group for selections
  max_cursors = 32,                  -- Maximum concurrent cursors
  namespace = 'vscode_style',        -- Namespace for extmarks
  
  ----------------------------------------------------------------------------
  -- BUFFER-LOCAL SETTINGS
  ----------------------------------------------------------------------------
  buffer_local = false,              -- Enable per-buffer configuration
  exclude_filetypes = {              -- Don't enable in these filetypes
    'help', 'terminal', 'qf', 'prompt'
  },
  include_filetypes = {},            -- Only enable in these (empty = all)
  
  ----------------------------------------------------------------------------
  -- FEATURE TOGGLES
  ----------------------------------------------------------------------------
  features = {
    selection = true,                -- Shift+arrow selections
    multi_cursor = true,             -- Multi-cursor functionality
    line_manipulation = true,        -- Alt+arrow line moves
    column_selection = true,         -- Column/block selection
  },
  
  ----------------------------------------------------------------------------
  -- KEYBINDING CONTROL
  ----------------------------------------------------------------------------
  enable_default_keymaps = true,     -- Use default VSCode keybindings
  respect_existing_maps = true,      -- Don't override user mappings
  
  disable_keymaps = {                -- Disable specific default bindings
    -- '<C-d>',
    -- '<C-S-l>',
  },
  
  keymaps = {                        -- Customize or disable bindings
    -- Customize:
    -- select_character_left = '<S-Left>',
    -- select_character_right = '<S-Left>',
    
    -- Disable:
    -- add_cursor_next = false,
    -- select_all_occurrences = false,
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
  show_cursor_count = false,         -- Show active cursor count
  cursor_count_format = 'Cursors: %d',
  cursor_count_position = 'statusline', -- or 'virtual_text'
  cursor_count_hl = 'Comment',
  
  ----------------------------------------------------------------------------
  -- CALLBACKS/HOOKS (for extensibility)
  ----------------------------------------------------------------------------
  on_setup = function() end,
  on_cursor_add = function(cursor) end,
  on_cursor_remove = function(cursor) end,
  on_selection_change = function(cursors) end,
  on_enter_insert = function() end,
  on_leave_insert = function() end,
  
  ----------------------------------------------------------------------------
  -- CUSTOM ACTIONS (advanced)
  ----------------------------------------------------------------------------
  actions = {
    -- my_custom_action = function() ... end,
  },
  
  action_overrides = {
    -- select_character = function(direction) ... end,
  },
  
  ----------------------------------------------------------------------------
  -- ADVANCED/DEBUG
  ----------------------------------------------------------------------------
  debug = false,
  log_level = 'warn',                -- 'trace', 'debug', 'info', 'warn', 'error'
})
```

---

## 📊 Priority Summary

### Must Fix Immediately (Blocker for "flexible & non-opinionated"):
1. ✅ Add comprehensive configuration system
2. ✅ Make all keybindings configurable/disableable
3. ✅ Fix documentation inconsistency (code-nvim vs vscode_style)
4. ✅ Add buffer-local/filetype-aware configuration
5. ✅ Implement callback/hook system

### Should Fix Soon (High Impact):
6. ✅ Remove duplicate `buf()` function
7. ✅ Add error handling throughout
8. ✅ Create plugin/ directory for auto-load
9. ✅ Make mapping strategy consistent
10. ✅ Add status indicator support

### Nice to Have (Medium Impact):
11. ✅ Add automated tests (busted/plenary)
12. ✅ Complete documentation
13. ✅ Add API documentation
14. ✅ Document undo/redo behavior
15. ✅ Add custom action support

### Low Priority (Polish):
16. ✅ Make namespace configurable
17. ✅ Add runtime disable/reload
18. ✅ Refactor code organization

---

## 🎯 Conclusion

The plugin has **solid core functionality** (all main features work), but **critically lacks flexibility and configurability** required for a "non-opinionated" tool.

**Current State:** 
- ✅ Feature-complete for basic VSCode-style editing
- ❌ Too opinionated (hardcoded everything)
- ❌ Not flexible (minimal configuration)
- ❌ Limited extensibility (no hooks/callbacks)

**To Meet Requirements:**
Focus on issues #1, #2, #3, #5, and #8 first. These are the blockers for achieving the "non-opinionated but very flexible" goal.

The technical implementation is sound, but the configuration layer needs significant expansion to allow users to:
- Use only the features they want
- Customize keybindings
- Extend functionality
- Integrate with other plugins
- Disable per-buffer/filetype

**Estimated Effort:** 2-3 days of focused work to address critical issues and make the plugin truly flexible.
