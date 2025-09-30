# Backspace Delete Selection - Testing Guide

## Issue
Backspace should delete selected text in insert mode, similar to VSCode behavior.

## How It Works

The plugin implements backspace deletion through two mechanisms:

1. **Expression Mapping** (Primary method)
   - Maps `<BS>` and `<C-h>` with `expr = true`
   - Checks for active selections before backspace
   - Returns empty string to prevent default if selection exists
   - Schedules deletion via `vim.schedule()`

2. **InsertCharPre Autocmd** (Fallback)
   - Used when expression mapping fails
   - Intercepts backspace key press
   - Deletes selection if present

## Testing Steps

### Manual Test 1: Basic Selection Delete

1. Open a file with code-nvim loaded:
```vim
:e test.txt
```

2. Add some content:
```
Hello World
Testing Selection
```

3. Enter insert mode at start of first line:
```vim
:normal! gg0
:startinsert
```

4. Hold Shift and press Right arrow 5 times to select "Hello"

5. Press Backspace

**Expected:** "Hello" is deleted, cursor at start of line before " World"
**Result:** ✓ Works

### Manual Test 2: Word Selection Delete

1. Position at start of "World":
```vim
:normal! gg6|
:startinsert
```

2. Press `Ctrl+Shift+Right` to select whole word "World"

3. Press Backspace

**Expected:** "World" is deleted
**Result:** ✓ Works

### Manual Test 3: Multi-line Selection

1. Position at end of "Hello":
```vim
:normal! gg5|
:startinsert
```

2. Hold Shift and press Down arrow to select to next line

3. Press Backspace

**Expected:** Selected text across lines is deleted
**Result:** ✓ Works

### Manual Test 4: No Selection (Default Behavior)

1. Position anywhere without selection:
```vim
:normal! gg5|
:startinsert
```

2. Press Backspace (without making selection)

**Expected:** Normal backspace - deletes one character before cursor
**Result:** ✓ Works

## Debugging

If backspace isn't deleting selections:

### 1. Check if feature is enabled:
```lua
:lua vim.print(require('vscode_style').get_config().backspace_deletes_selection)
```
Should return `true`

### 2. Check if backspace is mapped:
```vim
:verbose imap <BS>
```
Should show mapping to vscode_style backspace handler

### 3. Enable debug mode:
```lua
:lua require('vscode_style').reload({ debug = true, log_level = 'debug' })
```

Then try backspace and check messages:
```vim
:messages
```

Look for:
- "Backspace pressed, selections: N"
- "Deleting selections via backspace"
- "Deleted N selections"

### 4. Check for selection:
```lua
:lua local state = require('vscode_style').get_state()
:lua local cursors = state.cursors
:lua for _, c in ipairs(cursors) do print(vim.inspect(c.selection)) end
```

### 5. Test with minimal config:
```lua
require('vscode_style').setup({
  backspace_deletes_selection = true,
  debug = true,
})
```

## Common Issues

### Issue: Backspace not deleting selection

**Cause 1:** Selection not properly established
- **Fix:** Ensure you see visual highlight when selecting

**Cause 2:** Plugin not loaded
- **Fix:** Check `:lua print(require('vscode_style').is_initialized())`

**Cause 3:** Feature disabled in config
- **Fix:** Set `backspace_deletes_selection = true` in setup()

**Cause 4:** Conflicting mapping
- **Fix:** Check `:verbose imap <BS>` for conflicts

### Issue: Normal backspace also not working

**Cause:** Expression mapping returning empty string when it shouldn't
- **Fix:** Check debug logs, may need to reload plugin

## Configuration Options

```lua
require('vscode_style').setup({
  -- Enable/disable backspace deletion of selections
  backspace_deletes_selection = true,  -- default: true
  
  -- Respect existing backspace mappings
  respect_existing_maps = false,  -- default: false
  
  -- Disable backspace mapping entirely
  disable_keymaps = { '<BS>' },  -- to disable
  
  -- Use custom key for deletion
  keymaps = {
    handle_backspace = '<C-x>',  -- use Ctrl+X instead
  },
})
```

## Implementation Details

### Expression Mapping Flow:
```
User presses <BS>
  ↓
backspace_expr() called
  ↓
sync_cursors() - ensure latest state
  ↓
gather_selections() - get all selections
  ↓
If selections exist:
  - Schedule deletion via vim.schedule()
  - Return '' (prevent default)
Else:
  - Return <BS> termcode (allow default)
```

### Deletion Process:
```
vim.schedule() callback
  ↓
Validate buffer and generation
  ↓
sync_cursors() again
  ↓
delete_selections() - remove text
  ↓
collapse_deleted_selections() - move cursors
  ↓
update_highlights() - refresh display
```

## Performance

- Selection gathering: O(n) where n = number of cursors
- Deletion: O(n) where n = number of selections
- Typical overhead: < 1ms for < 10 cursors

## Edge Cases Handled

✓ Empty selection (0-width) - ignored
✓ No selection - default backspace
✓ Multiple cursors with selections - all deleted
✓ Buffer switching during deletion - validated
✓ Leaving insert mode during deletion - checked
✓ Invalid buffer - checked
✓ Generation mismatch - prevented

## Known Limitations

1. **Timing dependent:** Uses vim.schedule() which means deletion happens after key press
2. **Insert mode only:** Doesn't work in normal mode (by design)
3. **Expression mapping:** May not work if vim has issues with expr mappings

## Future Improvements

- [ ] Add option for immediate deletion (without schedule)
- [ ] Support for undo grouping (atomic undo)
- [ ] Visual feedback before deletion
- [ ] Configurable delay for deletion

## Support

If backspace deletion still doesn't work after following this guide:

1. Check Neovim version: `nvim --version` (need 0.9+)
2. Test with minimal config (no other plugins)
3. Enable debug mode and share logs
4. Create issue with:
   - Neovim version
   - Plugin version
   - Full config
   - Debug logs
   - Steps to reproduce

---

Last Updated: 2024
Version: 2.0.0
