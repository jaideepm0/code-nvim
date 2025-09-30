# Backspace Selection Delete - User Guide

## ✅ It's Fixed and Working!

The backspace selection delete feature has been thoroughly tested and is working correctly.
If you're experiencing issues, follow this guide.

## Quick Test

Run this command to verify it's working:

```bash
cd /path/to/code-nvim
./TEST_BACKSPACE_NOW.sh
```

You should see: `✅ ALL TESTS PASSED`

## Manual Test Steps

1. **Start Neovim with the plugin:**
   ```bash
   nvim
   ```

2. **Ensure plugin is loaded** (check your config has):
   ```lua
   require('vscode_style').setup({
     backspace_deletes_selection = true,  -- This must be true!
   })
   ```

3. **Create test content:**
   - Open a new file or buffer
   - Type: `Hello World` (in insert mode)
   - Press `Esc` to exit insert mode

4. **Position cursor:**
   - Press `0` to go to start of line
   - Press `i` to enter insert mode

5. **Create selection:**
   - **Hold Shift**
   - **Press Right Arrow** 5 times
   - You should see "Hello" highlighted (Visual highlight)

6. **Press Backspace:**
   - Press the Backspace key ONCE
   - Expected result: "Hello" is deleted, " World" remains

## Troubleshooting

### Issue: No visual highlight when pressing Shift+Arrow

**Problem:** Selection not being created

**Solutions:**
1. Check plugin is loaded:
   ```vim
   :lua print(require('vscode_style').is_initialized())
   ```
   Should return: `true`

2. Check feature is enabled:
   ```vim
   :lua print(require('vscode_style').get_config().features.selection)
   ```
   Should return: `true`

3. Check mappings exist:
   ```vim
   :verbose imap <S-Right>
   ```
   Should show mapping to vscode_style

### Issue: Backspace does nothing (selection stays)

**Problem:** Backspace not deleting selection

**Solutions:**
1. Check backspace feature enabled:
   ```vim
   :lua print(require('vscode_style').get_config().backspace_deletes_selection)
   ```
   Should return: `true`

2. Check backspace is mapped:
   ```vim
   :verbose imap <BS>
   ```
   Should show mapping to vscode_style

3. Enable debug mode:
   ```lua
   require('vscode_style').setup({
     backspace_deletes_selection = true,
     debug = true,
     log_level = 'debug',
   })
   ```
   
   Then try again and check messages:
   ```vim
   :messages
   ```
   
   You should see:
   ```
   [BACKSPACE] Pressed. Found 1 selection(s)
   [BACKSPACE] Deleting selections
   [BACKSPACE] Successfully deleted 1 selection(s)
   ```

4. If you see `[BACKSPACE] No selections, using normal BS`:
   - Selection wasn't created properly
   - Try the manual test steps again carefully
   - Make sure you see visual highlight before pressing backspace

### Issue: Only one character deleted (normal backspace)

**Problem:** Backspace is working but not recognizing selection

**This means:**
- Selection not being created, OR
- Selection being cleared before backspace

**Solutions:**
1. Verify selection exists:
   - After pressing Shift+Arrow, you MUST see highlighted text
   - If no highlight, selection doesn't exist

2. Check if you're leaving insert mode:
   - Backspace only works in INSERT mode
   - Don't press `Esc` after creating selection

3. Try with debug:
   ```lua
   require('vscode_style').setup({
     debug = true,
     log_level = 'debug',
   })
   ```
   Check `:messages` for `[BACKSPACE]` logs

### Issue: Plugin not loading

**Problem:** Setup not being called

**Solutions:**
1. Check your init.lua/init.vim calls setup:
   ```lua
   require('vscode_style').setup()
   ```

2. Check plugin is in runtimepath:
   ```vim
   :set runtimepath?
   ```
   Should include path to code-nvim

3. Try minimal config:
   ```bash
   nvim -u NONE -c "set rtp+=~/.config/nvim/plugged/code-nvim" \
        -c "lua require('vscode_style').setup()"
   ```

## Common Mistakes

### ❌ Wrong: Leaving insert mode before backspace
```
i (enter insert mode)
Shift+Right (select)
Esc (leave insert mode) ← WRONG!
Backspace ← Won't work in normal mode
```

### ✅ Correct: Stay in insert mode
```
i (enter insert mode)
Shift+Right (select)
Backspace ← Works! Still in insert mode
```

### ❌ Wrong: No visible selection
```
i (enter insert mode)
Right Right Right (no Shift) ← No selection created
Backspace ← Just normal backspace
```

### ✅ Correct: Must see highlight
```
i (enter insert mode)
Shift+Right Shift+Right (with Shift!) ← See highlight
Backspace ← Deletes selection
```

## Configuration Examples

### Minimal (default settings):
```lua
require('vscode_style').setup()
```

### With debug enabled:
```lua
require('vscode_style').setup({
  backspace_deletes_selection = true,
  debug = true,
  log_level = 'debug',
})
```

### Disable other features, keep backspace:
```lua
require('vscode_style').setup({
  backspace_deletes_selection = true,
  features = {
    selection = true,      -- Need this for Shift+Arrow
    multi_cursor = false,  -- Can disable other features
    line_manipulation = false,
  },
})
```

## Verification Commands

Run these in Neovim to verify everything is set up correctly:

```vim
" 1. Check plugin initialized
:lua print(require('vscode_style').is_initialized())
" Expected: true

" 2. Check backspace enabled
:lua print(require('vscode_style').get_config().backspace_deletes_selection)
" Expected: true

" 3. Check backspace mapping
:verbose imap <BS>
" Expected: Shows vscode_style mapping

" 4. Check selection mapping
:verbose imap <S-Right>
" Expected: Shows vscode_style mapping

" 5. Get full config
:lua vim.print(require('vscode_style').get_config())
" Shows all settings
```

## Still Not Working?

If you've tried everything above and it still doesn't work:

1. **Run the test script:**
   ```bash
   ./TEST_BACKSPACE_NOW.sh
   ```
   
   If tests pass but manual doesn't work, it might be:
   - Terminal key binding issue
   - Conflicting plugin
   - Configuration issue

2. **Test with minimal config:**
   Create `/tmp/test.vim`:
   ```vim
   set nocompatible
   set rtp+=/path/to/code-nvim
   lua require('vscode_style').setup({ debug = true })
   ```
   
   Run:
   ```bash
   nvim -u /tmp/test.vim
   ```

3. **Check for conflicts:**
   ```vim
   :verbose imap <BS>
   :verbose imap <S-Right>
   ```
   
   If multiple mappings shown, another plugin might be conflicting.

4. **Report the issue** with:
   - Neovim version: `:version`
   - Plugin version
   - Full config
   - Output of `:messages` after enabling debug
   - Steps to reproduce

## It Works!

If backspace deletion is working:
- ✅ You'll see visual highlight when selecting
- ✅ Backspace will delete the entire selection
- ✅ Cursor positioned where selection started

Enjoy VSCode-style editing in Neovim! 🎉

---

**Last Updated:** 2024  
**Version:** 2.0.1  
**Status:** Working ✅
