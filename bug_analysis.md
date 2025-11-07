# Bug Analysis: Failure to Delete Selection on Backspace/Delete

## 1. The Bug
Pressing `<BS>` or `<Del>` on a visual selection in insert mode does not delete the selection. Instead, it performs the native action (deleting the character before/after the cursor).

## 2. Summary of Failed (Reactive) Attempts
All previous attempts have been **reactive**. They have tried to intercept the `<BS>`/`<Del>` keypress *at the moment it is pressed* and then decide whether to act. All have failed due to a fundamental race condition.

*   **Attempt 1: `InsertCharPre` Autocommand:**
    *   **Reason for Failure:** This event **does not fire** for non-inserting control keys like `<BS>`. This approach was fundamentally incorrect.

*   **Attempt 2: Standard Asynchronous Keymap:**
    *   **Reason for Failure:** The Lua callback executed too late. Neovim's internal processing had already cleared the plugin's selection state.

*   **Attempt 3 & 4: Synchronous `<expr>` Mappings:**
    *   **Reason for Failure:** Even with a synchronous `<expr>` mapping, the race condition persisted. The final hypothesis is that Neovim's core input processing is so fast that it clears the plugin's custom selection state (which is based on extmarks) before *any* keymap evaluation can reliably query it.

**Conclusion:** All reactive approaches have failed. We cannot win the race condition by trying to intercept the keypress.

## 3. The New Approach: Proactive, Context-Sensitive Remapping
The new strategy is **proactive**. Instead of reacting to a keypress, we will change the environment *the moment a selection is made*, preparing for a potential deletion before it happens.

*   **How it works:**
    1.  **Activation**: The moment any text is selected by the plugin, a set of temporary, buffer-local keymaps for `<BS>` and `<Del>` will be created. These keymaps will point to a dedicated deletion function.
    2.  **Execution**: If the user presses `<BS>` or `<Del>` while this temporary keymap is active, our dedicated function is triggered, which deletes the selection.
    3.  **Deactivation**: The temporary keymaps are immediately removed under any of the following conditions:
        *   The selection is successfully deleted (the keymap's job is done).
        *   The user types a different character (which replaces the selection).
        *   The user moves the cursor, thereby breaking the selection.
        *   The user leaves insert mode.

This architecture sidesteps the race condition entirely. We are no longer trying to check for a selection and handle a keypress at the same time. By the time `<BS>` is pressed, the keymap is already in place and its only job is to delete. This is a more robust, state-aware design.
