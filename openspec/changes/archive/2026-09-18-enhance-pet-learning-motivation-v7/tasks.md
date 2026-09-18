## 1. Goal projection

- [x] 1.1 Add `PetLearningGoal` and pure progress projection for current textbook/unit goals.
- [x] 1.2 Map goal kinds to action labels, pet actions, and room outcome previews without a second reward ledger.
- [x] 1.3 Add migration-safe storage for goal presentation/completion lifecycle identifiers if needed.

## 2. Pet actions and room feedback

- [x] 2.1 Add a finite pet action state model and accessible reduced-motion rendering for invite, think, correct, incorrect, complete, and repeat states.
- [x] 2.2 Add semantic room feedback states for in-progress and completed goal outcomes, with one bounded transition per attempt.
- [x] 2.3 Integrate action sequencing into the fixed three-question practice without changing grading or answer selection.

## 3. Active invitation scheduling

- [x] 3.1 Implement deterministic, local-date-based invitation scheduling with daily presentation and acceptance cooldowns.
- [x] 3.2 Prioritize current mistakes, then the smallest unfinished current-unit goal, and suppress invitations when no useful action exists.
- [x] 3.3 Add skip/accept behavior to mode page and pet home while preserving neutral dismissal and current-textbook boundaries.

## 4. Goal-focused UI

- [x] 4.1 Add a current-unit goal card with progress, remaining amount, action, and room-result preview.
- [x] 4.2 Show the next goal after completion and connect it to the existing three-question or standard-practice entry point.
- [x] 4.3 Add one-time goal completion feedback without duplicate growth reward or repeated celebration.

## 5. Event instrumentation

- [x] 5.1 Extend the closed engagement event types and typed context for invitation skip, goal viewed, and goal-driven start.
- [x] 5.2 Record each new event once per presentation lifecycle and keep event writes offline/non-blocking.
- [x] 5.3 Extend metric and privacy tests for scheduling, goal events, deduplication, and prohibited fields.

## 6. Verification

- [x] 6.1 Add model, scheduler, widget, integration, migration, and reduced-motion tests for the new behavior.
- [x] 6.2 Run formatting, Flutter analysis, targeted tests, full Flutter tests, OpenSpec strict validation, and diff checks.

## 7. Review fixes

- [x] 7.1 Scope goal quick practice by current-unit chapter IDs and goal action.
- [x] 7.2 Reuse per-lesson pass semantics so unit completion matches `UnitMastery.isComplete`, and select the smallest unfinished goal inside the first incomplete unit.
- [x] 7.3 Split goal and invitation launch paths, including consistent goal-start instrumentation and goal-ID lifecycle handling.
- [x] 7.4 Fall back to the relevant standard-practice chapter when fewer than three compatible goal attempts exist.
- [x] 7.5 Wire complete and repeat pet actions into the actual completion dialog flow.
- [x] 7.6 Add regression coverage for multi-unit ordering, multi-lesson thresholds, scoped sessions, event consistency/lifecycle, fallback, and complete/repeat actions.
- [x] 7.7 Run formatting, analysis, full tests, OpenSpec strict validation, and diff checks after review fixes.
