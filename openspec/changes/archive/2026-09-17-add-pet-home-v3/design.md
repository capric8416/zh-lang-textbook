## Context

The current pet-home screen renders one preview and lets learners select an unlocked breed or decoration. Growth stages already provide a stable, global progression source. v3 should turn that screen into a small offline home with predictable visual rewards while remaining usable on mobile and desktop.

## Goals / Non-Goals

**Goals:**

- Provide three switchable rooms with distinct themes.
- Persist the selected room and derive furniture unlocks from major stages.
- Render furniture using lightweight Flutter widgets and fixed responsive layouts.
- Preserve all v2 profile fields and behavior.

**Non-Goals:**

- No freeform furniture placement, rotation, inventory management, currency, shop, personality, or social features.
- No negative pet states or rewards that affect mastery.

## Decisions

1. **Use stable room and furniture IDs.** Persist IDs rather than labels so copy and visuals can evolve without data migration.
2. **Keep one global furniture unlock set.** Stage-derived furniture is available across rooms, while each item declares its room and fixed slot. This avoids per-room progression complexity.
3. **Use fixed slots with responsive scaling.** A `Stack`/custom room widget maps slots to normalized coordinates. Automatic placement is deterministic and avoids drag state and accessibility problems.
4. **Normalize legacy profiles.** Missing room/furniture fields default to the living room and an empty furniture set; synchronization merges all items whose unlock stage is reached.
5. **Keep room switching local and instant.** Switching updates only the selected room and never changes learning progress or pet growth.

## Risks / Trade-offs

- [Small screens may crowd furniture] → use normalized slots, minimum spacing, and compact labels.
- [Future furniture changes may alter a layout] → keep slot IDs stable and allow catalog revisions without changing profile data.
- [Too many visual rewards may distract] → limit v3 to three rooms and a small catalog.

## Migration Plan

Read v2 profiles with default room `living-room` and no furniture selections. On the next silent synchronization, derive unlocked furniture from the existing major stage and persist the normalized profile. Existing growth, breed, decoration, and claimed events remain unchanged.

## Open Questions

Later versions may add more rooms or furniture sets, but v3 does not need a furniture editor or pet personality model.
