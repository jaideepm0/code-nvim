# Project Summary and Critical Technical Review

Repository: `code-nvim`
Purpose: Provide VSCode‑style, insert‑mode centric, multi‑cursor and selection workflows inside Neovim using only Lua and standard APIs.

---
## 1. Repository Inventory

Top-level files:
- `init.lua` – Plugin entrypoint, auto-calls setup.
- `lua/vscode_style/init.lua` – Public setup routine, keymap installation, autocmd wiring, shared state.
- `lua/vscode_style/actions.lua` – Monolithic implementation of all editing, selection, movement, multi-cursor text manipulation, indentation logic, and search helpers (>1100 lines).
- `lua/vscode_style/multi_cursor.lua` – Core multi-cursor state manager (extmarks, selections, snapshots, highlights, buffer switching).
- `INSTRUCTIONS.md` – Specification describing required VSCode keybindings and architecture blueprint.
- `README.md` – User-facing description (partial mismatch with actual flexibility claims).
- `TODO.md` – (Present but not yet inspected for dynamic logic—unused in runtime.)
- `tests/` – Manual checklist (`tests.md`) and an unrelated Python script (`main.py`) referencing external OpenAI API – out of scope for plugin.
- `summary.md` – (This file) Analytical synthesis.

No automated test harness; no CI; no version gating.

---
## 2. Architectural Overview

### 2.1 State Model
A single mutable `state` table (in `vscode_style/init.lua`) contains:
- `ns`: Namespace id for extmarks & highlights.
- `cursors`: Array of cursor objects (each holds extmark id, position, anchor, selection, selection stack, highlight id, is_primary flag).
- `config`: Merged user + default settings (`selection_hl`, `max_cursors`).
- `snapshots`: Buffer-indexed table for restoring cursor states upon mode re-entry.
- Flags: `column_selecting`, `column_anchor`, `backspace_mapped`.

### 2.2 Modules
- `multi_cursor.lua` encapsulates low-level cursor lifecycle: creation, positioning, selection highlight application, buffer change resilience, snapshot save/restore.
- `actions.lua` builds higher-level semantics (word movement, line movement, multi-cursor search, indentation, replace-on-type, backspace logic, expansion heuristics, column selection, duplication, deletion). It also reproduces some baseline text-object logic.

### 2.3 Event & Input Flow
1. Insert-mode keymaps call small anonymous closures that delegate to `actions.*`.
2. `InsertCharPre` interception (`on_insert_pre`) suppresses normal character insertion when selections exist, performing a multi-cursor replacement flow instead.
3. `InsertLeave` saves snapshot, clears selections & highlights.
4. `InsertEnter` restores snapshot (unconditionally) for current buffer.
5. Mouse events for column selection (`<S-M-LeftDrag>` / `<S-M-LeftRelease>` and `<M-LeftMouse>`) adjust multi-cursor sets.

### 2.4 Selection & Cursor Mechanics
- Selections are simulated (not actual Visual mode), represented by pairs of positions (`anchor`, `active`).
- Extmarks track physical cursor points (one per cursor). Highlights of type `selection_hl` emulate visual selection.
- Selection expansion uses a stack (`selection_stack`) enabling shrink (pop) operations.

### 2.5 Editing Pipeline (Replace-On-Type)
When a character is typed and there are selections:
1. `InsertCharPre` stores typed char, sets `vim.v.char=''` to suppress default insertion.
2. Gathers selection ranges; schedules a deferred `vim.schedule` callback.
3. In callback, deletes all selections (descending order), collapses cursors to selection starts, inserts new text for each cursor (descending point order), adjusts positions, reapplies highlights.
4. This per-cursor insertion is not wrapped in an undo join → generates multiple undo steps.

### 2.6 Line Move / Duplicate / Delete
- Movement, duplication, deletion compute consolidated line ranges from cursors/selections, deduplicate, then mutate buffer lines and reposition cursors accordingly.
- Duplicate does not currently preserve or extend selection semantics to the new clone.

### 2.7 Search & Multi-Cursor Addition
- `Ctrl+D` (add_selection_to_next_match): naive forward literal search using `string.find` with `vim.pesc` escaping.
- `Ctrl+Shift+L` (select_all_occurrences): full-buffer scan collecting literal matches, truncated implicitly by `max_cursors` when replaced.
- Overlapping occurrences not specially handled; word-boundary logic absent; no wrap-around search.

### 2.8 Column (Box) Selection
- Implemented only with mouse drag + modifiers. For each line between anchor and release, a new cursor & a same-line selection is established. Typing performs independent per-line edits rather than a structural rectangular insert (acceptable but differs from VSCode when inserting multi-char text).

---
## 3. Keybinding Coverage vs Spec
Implemented per INSTRUCTIONS:
- Character, line, word selection (Shift+Arrows, Ctrl+Shift+Arrows).
- Line boundary, file boundary selections (Shift+Home/End, Ctrl+Shift+Home/End).
- Line move (Alt+Up/Down), copy line (Shift+Alt+Up/Down), delete line (Ctrl+Shift+K).
- Multi-cursor add via Alt+Click, Ctrl+Alt+Up/Down.
- Ctrl+D next match, Ctrl+Shift+L all occurrences.
- Shift+Alt+Right/Left expand/shrink selection (custom heuristic).
- Shift+Alt+LeftDrag/Release column selection.

Additional (not specified but present):
- Tab / Shift+Tab indentation logic inside selections.
- Backspace replacement logic across selections.

Missing nuances / divergences:
- No keyboard-only rectangular selection (e.g., sustaining Shift+Alt+Down without mouse to build rectangle).
- Expand selection does not progress through structured syntactic scopes beyond indentation heuristic.
- No advanced word navigation semantics (camelCase, punctuation segmentation).

---
## 4. Strengths
- Pure Lua, no external dependencies.
- Extmark-based cursor tracking robust across buffer edits.
- Clear separation (conceptually) between core cursor primitives and action layer.
- Defensive clamping of line/column indices reduces runtime errors.
- Snapshot system persists multi-cursor context across mode transitions (useful for some workflows).
- Consistent highlight renewal ensures visual sync.

---
## 5. Weaknesses / Issues (Detailed)
### 5.1 Flexibility & Configuration
- Only two exposed settings: `selection_hl`, `max_cursors`.
- Hardcoded keymaps: user cannot remap or disable subsets — contradicts “non-opinionated but very flexible.”
- No toggles for snapshot persistence, Tab override, notification verbosity, wrap search, indentation width override, undo grouping policy.

### 5.2 Monolithic Actions Module
- `actions.lua` >1100 lines; multi-responsibility (movement, structural selection, search, editing, indentation, scheduling). Harder to test incrementally or extend (e.g., adding tree-sitter aware expansions).

### 5.3 Selection & Expansion Heuristics
- Expand selection cycles: word → full line(s) → indentation block → (stops). VSCode typically escalates to progressively larger syntactic constructs (brackets, function, class, file).
- Shrink only pops stack but no maximum stack depth; potential memory growth if user repeatedly expands.

### 5.4 Search & Match Logic
- Literal search only; missing word-boundary logic causing partial token matches.
- Overlapping matches not addressed.
- No wrap-around or configurable search direction.
- Ctrl+D noisy termination message each time end-of-file reached (potential distraction).

### 5.5 Undo/Redo Granularity
- Multi-cursor replacements & indent/dedent operations produce multiple independent buffer change steps → user must press undo repeatedly. No use of `undojoin` or batched atomic edit segments.

### 5.6 Performance Considerations
- Re-highlighting every cursor on each change (full refresh) instead of diff-based updates.
- Full scan of buffer for select_all_occurrences regardless of hitting max_cursors early—could break early.
- Frequent scheduled callbacks for typed characters; potential queue backlog with extremely fast input.

### 5.7 Edge Case Logic
- Off-by-one logic in selection collapsing when selection end falls at column 0 on next line boundary.
- Duplicate line action does not maintain selection across duplicated content (user expectation mismatch vs VSCode).
- Column selection for lines shorter than anchor column sets anchors possibly beyond line end (clamped later) — safe but semantics inconsistent (should preserve column intent explicitly).
- Extmark recreation fallback in `sync_cursor_from_extmark` does not reapply highlight if selection existed.

### 5.8 Word Movement Simplification
- Word boundaries: three classes only (space / word / symbol). Hyphens, dots, camelCase boundaries, multi-byte graphemes ignored; reduces parity with VSCode navigation/selection.

### 5.9 Snapshot Semantics
- Automatic restore of prior cursor arrangement on every `InsertEnter` may feel surprising; no opt-out.
- Snapshot per buffer stored in-memory only; not versioned or session-persisted.

### 5.10 Testing & Tooling
- Only a manual checklist; no automated regression tests.
- No CI setup, no linting or stylua formatting enforcement.
- Python script in tests/ irrelevant; increases potential for accidental dependency confusion.

### 5.11 Documentation Gaps
- README omits description of mouse gestures and limitations.
- Claims flexibility not yet realized in code.
- Does not mention differences vs real VSCode (e.g., limited expand semantics, undo granularity).
- No CHANGELOG, no usage caveats (terminal Alt+mouse compatibility, <C-S-k> portability).

### 5.12 Maintainability
- Lack of modular decomposition impedes adding new features like bracket-level expansion, text object integration, or tree-sitter optional providers.
- Mixed concerns: search, indentation, structural expansion logic all co-located.

### 5.13 Potential User Experience Friction
- Frequent notifications for benign end-of-search cases.
- Inconsistent duplication selection handling may reduce trust.
- Multi-step undo after single conceptual action feels “laggy.”

---
## 6. Code Quality Observations
- Generally defensive bounds checking (good).
- Clear helper naming (move_word_left_position, gather_selections, etc.).
- Some repeated logic (e.g., sorting selections descending before mutation) could be extracted further.
- Long functions (e.g., `on_insert_pre`) intermix control flow for multiple edge cases; could benefit from early-return segmentation and subroutine extraction.
- Complexity concentrated in actions.lua without internal submodules.

---
## 7. Concurrency & Scheduling Notes
- Uses `vim.schedule` to defer selection replacement after `InsertCharPre` and backspace operations — reduces reentrancy risk but introduces race windows when buffer changes mid-schedule. Generation token guard (`current_generation`) mitigates cross-buffer interference.
- No explicit cancellation if buffer swapped rapidly several times; leftover scheduled callbacks may become no-ops (safe) but still overhead.

---
## 8. Data Structures & Algorithms
- Cursor set: array sorted by line/col; operations O(n log n) for sorting after updates (n <= 32 → negligible).
- Selection gather + deletion: sorts descending for safe mutation — appropriate.
- Occurrence scans: naive linear scan of all lines each invocation; acceptable for small/medium files; could short-circuit once max cursors reached.
- Indentation modification: brute-force prefix manipulation; no detection of mixed indentation anomalies.

---
## 9. Extmarks & Highlight Handling
- Each cursor has two extmark usages: one for position, optionally one for selection highlight.
- Reapplies highlight each update; uses non-gravity to keep anchors stable.
- Does not consolidate adjacent highlight ranges (fine for clarity).
- Losing highlight extmark recreated only through full update cycles; rare edge if extmark deletion fails silently.

---
## 10. Security / Scope Concerns
- Unrelated `tests/main.py` imports OpenAI dependencies; invites environment leakage or accidental secret usage. Best isolated or removed from plugin distribution.
- No dynamic code execution beyond Neovim API interaction; low risk inside Neovim sandbox.

---
## 11. Prioritized Improvement Roadmap

### Phase 1 (Foundational Flexibility & UX)
1. Configurable keymap layer (allow disabling or remapping each action).
2. Option toggles: `enable_snapshots`, `wrap_search`, `group_undo`, `auto_indent_tab`, `notify_on_search_end`.
3. Duplicate line: replicate VSCode selection retention semantics.
4. Atomic undo: bracket multi-cursor edits with `undojoin` or a single scheduled compound edit.
5. Silent end-of-search by default; notification behind configurable verbosity setting.
6. Add user hook events: `on_cursors_changed`, `on_selection_changed`.

### Phase 2 (Feature Parity Enhancements)
7. Pluggable expand providers (word → quotes/brackets → parent node via tree-sitter (optional) → indentation block → file).
8. Improved word boundary logic (configurable regex + camelCase segmentation option).
9. Keyboard rectangular selection fallback (e.g., Shift+Alt+Arrow incremental vertical expansion without mouse).
10. Overlapping occurrence and word-boundary-aware selection for Ctrl+D when original selection is a “word.”

### Phase 3 (Performance & Maintainability)
11. Split `actions.lua` into modules: `movement.lua`, `selection.lua`, `edit.lua`, `search.lua`, `indent.lua`, `expand.lua`.
12. Incremental highlight updates (only changed cursors/selections).
13. Early exit in `collect_all_occurrences` after accumulating `max_cursors`.
14. Add bench / profiling hooks (optional dev flag) to measure schedule latency.

### Phase 4 (Quality & Ecosystem)
15. Automated tests (Plenary): unit tests for selection math, word movement, duplication, undo grouping; integration tests with ephemeral buffers.
16. Add CI (GitHub Actions) with minimal Neovim matrix (0.9, stable, nightly) ensuring backward compatibility.
17. Provide CHANGELOG, semantic versioning, and documented breaking change policy.
18. Expand README with limitations & configuration reference table.

### Phase 5 (Advanced / Optional)
19. Optional tree-sitter integration for structural expansion (graceful fallback if not available).
20. Serialization of snapshot state across sessions (opt-in).
21. Visual indicator (virtual text or status component) of cursor count & expansion depth.

---
## 12. Concrete Quick Wins
- Add config table merging for user keymap overrides before mapping.
- Wrap multi-cursor edit (selection deletion + insertion) inside single undo block by using `vim.api.nvim_buf_call` + `vim.cmd('undojoin')` after first change.
- Modify duplicate logic: after inserting copy, reassign selections to cloned range & reposition primary cursor like VSCode.
- Add boolean config controlling snapshot restore on `InsertEnter`.
- Silence or gate the end-of-search notification.
- Document mouse limitations and terminal caveats explicitly.

---
## 13. Risk Assessment of Current State
| Area | Risk | Impact | Mitigation Priority |
| --- | --- | --- | --- |
| Undo Granularity | Medium | Frustrating UX undo loops | High |
| Lack of Config | High | Adoption barrier | High |
| Monolithic File | Medium | Slows feature evolution | Medium |
| Simplistic Expansion | Low (core still works) | Reduced parity expectation | Medium |
| Search Literal Only | Medium | Unexpected matches / misses | Medium |
| Performance on Large Files | Low (n <= 32 cursors) | Acceptable but future risk | Low |
| Snapshot Surprise | Medium | Confusion when re-entering insert | Medium |
| Extraneous Python Script | Low security / clarity risk | Minor confusion | Low |

---
## 14. Suggested Configuration Schema (Future Draft)
```lua
require('vscode_style').setup({
  selection_hl = 'Visual',
  max_cursors = 32,
  enable_snapshots = true,
  group_undo = true,
  wrap_search = false,
  notify = { search_end = false, truncation = true },
  keymaps = {
    select_char_left = '<S-Left>',
    select_char_right = '<S-Right>',
    move_line_up = '<M-Up>',
    move_line_down = '<M-Down>',
    duplicate_line_up = '<S-M-Up>',
    duplicate_line_down = '<S-M-Down>',
    delete_line = '<C-S-k>',
    add_cursor_up = '<C-M-Up>',
    add_cursor_down = '<C-M-Down>',
    add_next_match = '<C-d>',
    select_all_occurrences = '<C-S-l>',
    expand_selection = '<S-M-Right>',
    shrink_selection = '<S-M-Left>',
  },
  word = { camel_case = true, extra_boundary_chars = '-' },
  expand_providers = { 'word', 'quotes', 'brackets', 'indent', 'buffer' },
})
```

---
## 15. Summary
The plugin successfully establishes a functional multi-cursor & VSCode-inspired insert-mode workflow using robust extmark mechanisms and careful selection simulation. However, to fulfill its stated goal of being “non-opinionated but very flexible,” it requires a broadened configuration layer, improved semantic expansion, more natural multi-cursor duplication/undo semantics, and architectural refactoring for maintainability. Addressing the outlined weaknesses—particularly configurability, undo grouping, search refinement, and modularization—will materially elevate developer trust and adoption.

---
## 16. Actionable Checklist (Condensed)
1. Add configuration-driven keymap and feature toggles.
2. Implement grouped undo for multi-cursor edits.
3. Preserve selection on line duplication.
4. Silence or gate non-critical notifications.
5. Extract modules from actions.lua.
6. Improve expand/shrink semantics (provider chain).
7. Optimize highlight refresh & early exit on excessive occurrences.
8. Introduce automated tests for core selection & edit invariants.
9. Document limitations & terminal compatibility.
10. Remove unrelated Python test script from distribution scope.

---
Prepared to assist further with any of the above implementation phases.
