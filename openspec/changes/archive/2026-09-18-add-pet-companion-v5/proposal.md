## Why

The pet system already rewards learning, but it behaves mainly as a progress display: the companion has no learner-chosen identity, does not clearly explain the next unlock, and offers little motion or initiative outside milestone celebrations. Strengthening these moments can turn the existing three-question flow into a warmer invitation to learn without adding pressure, currencies, or maintenance chores.

## What Changes

- Let learners name their pet and use that name across the dashboard, pet home, invitations, and celebrations.
- Show a concrete next-unlock goal based on the next major-stage breed, decoration, or furniture and the current textbook's remaining unit progress.
- Let the pet offer one contextual three-question invitation using the existing current-textbook selector and practice page.
- Add brief, non-blocking companion reactions after any completed quick-practice session, even when no mastery milestone is crossed.
- Give actionable furniture small reduced-motion-aware idle cues so children can discover the learning entries.
- Preserve the existing no-decay, no-currency, no-streak, and no-punishment model.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `pet-growth`: Persist and present a learner-chosen pet name, concrete next-unlock guidance, and ordinary quick-session companion feedback.
- `pet-home`: Support naming, proactive learning invitations, and discoverable animated learning furniture.
- `pet-quick-practice`: Allow pet invitations to launch the existing fixed three-question activities and report a lightweight completion reaction.

## Impact

The change affects the pet profile schema, growth synchronization, dashboard card, pet home and room scene widgets, quick-practice launch/completion plumbing, celebration presentation, and related model/store/widget tests. It adds no network service, native dependency, new reward ledger, or textbook format change.
