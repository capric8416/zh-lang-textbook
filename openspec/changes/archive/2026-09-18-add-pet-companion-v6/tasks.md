## 1. Engagement event foundation

- [x] 1.1 Add versioned engagement-event, typed-context, delivery-state, anonymous-install, and session identifier models with tolerant JSON serialization.
- [x] 1.2 Implement a SharedPreferences-backed event repository with idempotent append, monotonic sequence, 90-day/1,000-event retention, acknowledged-first pruning, and corrupt-record recovery.
- [x] 1.3 Implement pure funnel projections for invitation click-through, quick completion, voluntary repeat, and next-day return.
- [x] 1.4 Add model, privacy allowlist, deduplication, retention, corruption, and metric-projection tests.

## 2. Companion mission and persistent room state

- [x] 2.1 Add deterministic three-step companion mission models for invitation and furniture launch sources without changing quick-practice attempt selection.
- [x] 2.2 Extend the pet profile/store with backward-compatible semantic furniture states, pending unlock reveals, last visit date, and last completed mission kind.
- [x] 2.3 Update growth synchronization to create new furniture reveal markers idempotently and preserve acknowledged legacy state.
- [x] 2.4 Add tests for mission derivation, legacy migration, semantic furniture activation, reveal acknowledgment, and repeated synchronization.

## 3. In-practice companion experience

- [x] 3.1 Pass companion mission and launch metadata into fixed three-question practice from mode-page invitations and pet-home furniture.
- [x] 3.2 Add an unobtrusive named-pet practice companion with idle, one-shot thinking, correct celebration, and incorrect encouragement states that reset per question.
- [x] 3.3 Advance mission presentation after every graded attempt regardless of correctness and commit the target furniture's active state only after all three attempts complete.
- [x] 3.4 Add an optional repeat-three-questions action after completion while keeping dismissal neutral and preserving normal grading, mastery, mistake, and growth behavior.
- [x] 3.5 Add widget tests for thinking timing, correct/incorrect reactions, mission advancement, reduced motion, early exit, completion, and voluntary repeat.

## 4. Living room feedback and return variation

- [x] 4.1 Render semantic active variants for the lamp, bookcase, and flower pot plus a one-time newly unlocked furniture reveal with a reduced-motion fallback.
- [x] 4.2 Derive a stable daily pet position and friendly greeting without streak, missed-day, hunger, or disappointment language.
- [x] 4.3 Persist visit continuity, recognize only exact next-day returns, and keep same-day revisits stable and idempotent.
- [x] 4.4 Add widget and store tests for active furniture visuals, reveal acknowledgment, same-day stability, next-day return, long-gap neutrality, and clock rollback.

## 5. Engagement instrumentation

- [x] 5.1 Record companion-surface and invitation-presentation events once per presentation lifecycle without logging pet names or free-form content.
- [x] 5.2 Record quick start, early exit, completion, and voluntary repeat events with stable session correlation and typed launch context.
- [x] 5.3 Record next-day return events once per eligible date transition and verify all event capture remains offline and non-blocking.
- [x] 5.4 Add integration tests covering the complete invitation-to-completion funnel, duplicate rebuild suppression, repeat flow, and prohibited-field absence.

## 6. Verification

- [x] 6.1 Format changed Dart files and run OpenSpec strict validation, Flutter analysis, targeted tests, and the full Flutter test suite.
