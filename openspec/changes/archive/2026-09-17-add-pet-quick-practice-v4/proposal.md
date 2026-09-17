## Why

Pet-home furniture is currently visual only. Giving a few furniture items focused learning actions can connect the companion space back to study while keeping each visit short, predictable, and pressure-free.

## What Changes

- Pass the selected textbook context into pet home.
- Make selected furniture open focused actions for that current textbook only.
- Add a fixed three-question quick-practice session.
- Select questions in priority order: current mistakes, unmastered questions, least-practiced questions, then mastered questions as fallback.
- Let furniture narrow the activity: bookcase for mixed review, toy box for mistake-first review, character wall for hanzi/pinyin, and flower pot for read-aloud content.
- Record answers through the existing progress, mistake, mastery, and pet-growth systems.
- Preserve completed answers when a learner exits before all three questions.
- Add no separate currency, score, streak, or quick-practice progression.

## Capabilities

### New Capabilities

- `pet-quick-practice`: Current-textbook three-question selection, execution, completion, and early-exit behavior.

### Modified Capabilities

- `pet-home`: Furniture becomes accessible learning entry points while retaining room switching and automatic placement.

## Impact

- Flutter mode-page navigation, pet-home screen and furniture scene, practice selection/session flow, existing progress storage, mastery synchronization, and tests.
- No new dependency, network requirement, native-library change, or independent reward ledger.
