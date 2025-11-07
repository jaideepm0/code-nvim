# Bug Analysis: Failure to Delete Selection on Backspace/Delete

**1. The Bug:**
Pressing `<BS>` or `<Del>` on a visual selection in insert mode does not delete the selection. Instead, it performs the native action (deleting the character before/after the cursor).

**2. Summary of Failed Attempts:**

*   **Attempt 1: `InsertCharPre` Autocommand:**
    *   **Method:** Intercepted the keypress in the `on_insert_pre` function.
    *   **Reason for Failure:** The `InsertCharPre` event is designed for character *insertion* and **does not fire** for non-inserting control keys like `<BS>` or `<Del>`. This approach was fundamentally flawed.

*   **Attempt 2: Standard Asynchronous Keymap:**
    *   **Method:** A standard insert-mode keymap (`<BS>`) was mapped to a Lua callback function.
    *   **Reason for Failure:** **Race Condition.** Neovim's internal processing for a non-insertion key clears the plugin's custom selection state *before* the asynchronous Lua callback is executed. The callback always saw an empty selection.

*   **Attempt 3: Synchronous `<expr>` Mapping with `nvim_buf_call`:**
    *   **Method:** An `<expr>` mapping was used to synchronously call a Lua function. This function used `vim.api.nvim_buf_call` to perform the deletion logic in a safe context.
    *   **Reason for Failure:** **Deferred Execution Race Condition.** While the `<expr>` mapping itself is synchronous, the use of `nvim_buf_call` schedules the deletion logic to run at a later point in the event loop. This small delay was enough for Neovim to clear the selection state, causing the fix to fail.

**3. Root Cause Analysis:**
The core problem is that the plugin's selection state (managed via highlights/extmarks) is extremely transient when a non-inserting key is pressed. Neovim's default handling appears to clear this state almost immediately. Any solution that defers the deletion logic, even slightly (like `nvim_buf_call` or `vim.schedule`), will fail.

**4. The New, Robust Approach: Fully Synchronous Direct Manipulation**

Based on these findings, the only viable solution is an `<expr>` mapping that performs the buffer manipulation **directly and immediately**, without any deferred execution.

*   **How it will work:**
    1.  An `<expr>` mapping for `<BS>` and `<Del>` will synchronously call a new Lua handler.
    2.  This handler will check if a selection exists.
    3.  If it does, the handler will **immediately** call the internal helper functions (`delete_selections`, `collapse_deleted_selections`, etc.) to modify the buffer directly within the same synchronous execution block.
    4.  The entire operation will be wrapped in `pcall` and `undojoin` for safety and correct undo history.
    5.  The handler will then return an empty string (`''`) to Neovim, consuming the original keypress.
    6.  If no selection exists, the handler will immediately return the original key's termcode (e.g., `<BS>`), allowing the default action to proceed.

This approach is designed to be the fastest possible intervention, eliminating any opportunity for Neovim's event loop to interfere with the plugin's state.
