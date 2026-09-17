## Why

The practice experience needs a lightweight, child-friendly motivation loop that rewards genuine learning progress without adding badges, currencies, shops, or punitive mechanics. A single dog companion can make lesson and unit completion visible and emotionally engaging while reusing the existing per-textbook practice history.

## What Changes

- Add one persistent dog companion with global growth points and one major growth stage for every completed textbook unit.
- Calculate lesson mastery from unique practice questions first answered correctly, with one-time milestones at 60%, 80%, 90%, and 100%.
- Treat 60% as lesson completion; complete a unit only when every eligible lesson in that unit reaches 60%.
- Show a compact dog growth card in the learning mode page with growth points and current textbook progress.
- Show a bottom-right dog run/reaction animation when a lesson reaches a new milestone, using increasingly rare expressions and colors at higher thresholds.
- Show a full-screen confetti celebration when a unit is completed.
- Persist awarded growth events and played celebrations so repeated answers, navigation, and app restarts cannot farm rewards or replay celebrations.
- Structure pet identity and visual state so common dog and cat breeds can be added later, while shipping only one default dog in v1.
- Do not add badges, maps, shops, feeding, hunger, streak punishment, regression, or multiple pets in v1.

## Capabilities

### New Capabilities

- `learning-mastery`: Derive stable lesson and unit completion from existing question progress and emit idempotent milestone events.
- `pet-growth`: Persist and present the default dog, growth points, major stages, milestone reactions, and unit celebrations.

### Modified Capabilities

None.

## Impact

- Flutter practice recording and mode-page presentation.
- SharedPreferences persistence for pet rewards and celebration history.
- New pet model, progress service, reusable pet card, and celebration overlay widgets.
- A code-rendered default-dog visual and widget tests for milestone thresholds, idempotency, navigation, and celebrations.
- No changes to package identifiers, native build integration, speech/OCR engines, or existing practice-progress serialization.
