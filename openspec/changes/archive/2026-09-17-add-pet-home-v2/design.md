## Context

The v1 pet feature stores one global dog profile and derives growth from learning mastery. The mode page presents the dog and milestone feedback, but the companion has no dedicated space or learner-controlled personalization. v2 must remain offline, preserve existing profiles, and avoid coupling pet features to practice correctness or curriculum data.

## Goals / Non-Goals

**Goals:**

- Add a dedicated pet-home screen reachable from the existing growth card.
- Add a version-tolerant catalog of dog and cat appearances and learning-earned decorations.
- Derive unlocks deterministically from the existing major growth stage and persist only learner selections.
- Provide short, non-competitive tap interactions with reduced-motion support.

**Non-Goals:**

- No shop, currency, feeding, hunger, decay, timers, network calls, or audio.
- No change to mastery scoring, textbook progress, native libraries, or package identifiers.
- No image assets or runtime dependencies; visuals remain code-rendered.

## Decisions

1. **Keep the profile global and migrate in place.** Add optional v2 fields to the existing JSON profile. Missing fields read as default dog, default decoration, and stage-derived unlocks. This preserves v1 files and avoids a second store.
2. **Use stable catalog IDs.** Breed and decoration IDs, not display names, are persisted. A catalog maps IDs to species, labels, colors, and appearance descriptors, allowing future breeds without schema changes.
3. **Compute unlocks from majorStage.** The growth synchronizer merges the deterministic unlock set after applying rewards. Re-running synchronization is idempotent and repairs profiles created by older versions.
4. **Persist selections only when unlocked.** Store methods validate requested IDs against the profile's unlock sets; invalid selections fall back to the current selection. Growth points, claimed events, and mastery remain untouched.
5. **Make interactions transient.** Pet-home buttons drive a short local animation/message and never write a reward or cooldown. `MediaQuery.disableAnimations` produces an immediate static response.
6. **Reuse `PetAvatar`.** Breed and decoration descriptors are passed into the existing painter so mode-page and home-page visuals share one rendering path. A small catalog is sufficient for v2 and can be expanded independently.

## Risks / Trade-offs

- [Older or malformed profile JSON] → tolerate missing/unknown IDs and always retain the default dog.
- [Unlocks changing if stage rules change] → keep thresholds and IDs centralized and test deterministic mappings.
- [Code-rendered cat/dog visuals are stylized] → prioritize clear color/marking differences and leave richer assets for a later version.
- [Home interactions could distract from study] → keep them optional, instant, and free of progression pressure.

## Migration Plan

Read v1 profiles as-is, derive stage-appropriate unlocks on the next silent synchronization, and save only if the normalized profile differs. Existing growth points, stages, and claimed events are never reset. Removing the feature later can ignore the extra JSON fields without affecting practice data.

## Open Questions

Future releases can decide whether to add more breeds, learner-created decorations, or additional interaction animations; none are required for v2.
