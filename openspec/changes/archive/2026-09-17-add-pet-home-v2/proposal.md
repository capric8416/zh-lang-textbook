## Why

The first pet-growth release gives learners a single dog and milestone celebrations, but the companion is still mostly a passive indicator. A small pet-home space can turn the existing growth into an ongoing relationship while giving children meaningful, non-random ways to personalize the companion.

## What Changes

- Add a dedicated pet-home page reachable from the growth card.
- Extend the local pet profile with selectable dog/cat breed appearances and deterministic unlocks tied to learning growth stages.
- Let learners switch among unlocked breeds without resetting growth points or curriculum progress.
- Add lightweight learning-earned decorations (collars, scarves, and simple backgrounds) with deterministic unlocks.
- Add a few tap-triggered, non-competitive pet interactions with short animations and no resource cost, cooldown penalty, hunger, or decay.
- Keep the default dog available permanently and preserve all v1 profile data through migration.

## Capabilities

### New Capabilities

- `pet-home`: Pet-home navigation, breed/decor selection, and lightweight interactions.

### Modified Capabilities

- `pet-growth`: Extend the profile and reward synchronization with unlocked appearances and decorations while retaining existing growth and celebration behavior.

## Impact

- Flutter pet models, SharedPreferences store, growth synchronization, mode-page card, and new pet-home screen/widgets.
- Code-rendered pet appearance descriptors for a small v2 catalog: default dog, Shiba Inu, Corgi, Golden Retriever, and tabby cat.
- No new runtime dependency, network requirement, or change to package identifiers, practice progress, speech, OCR, or native builds.
