## Why

Pet home v2 adds personalization, but it is still primarily a selection screen. A small set of switchable rooms and automatically unlocked furniture can make learning progress feel visible and rewarding without adding pressure or complex game systems.

## What Changes

- Add switchable living room, study room, and yard spaces.
- Add a deterministic furniture catalog with stage-based unlocks.
- Automatically place unlocked furniture in stable room layouts; no drag-and-drop editing.
- Persist the selected room while preserving existing pet, breed, decoration, and growth data.
- Keep interactions lightweight and do not add personality, currency, shops, hunger, decay, or penalties.

## Capabilities

### New Capabilities

- None.

### Modified Capabilities

- `pet-home`: Extend pet home with rooms and automatically placed furniture.
- `pet-growth`: Extend stage unlocks with learning-earned furniture while retaining existing rewards.

## Impact

- Flutter pet profile models, growth synchronization, local persistence, pet-home screen, and code-rendered room/furniture widgets.
- No new dependencies, assets, network services, or changes to practice/native modules.
