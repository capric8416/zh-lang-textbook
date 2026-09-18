## Context

The existing pet profile is global and local, while learning progress is scoped by textbook. `ModePage` already has the current textbook, catalog, progress, mastery, and pet profile; `PetHomePage` has the same context plus furniture launch actions. Quick practice already returns a completion result and ordinary milestone celebrations already render pet expressions. v5 should compose those pieces and add ephemeral feedback rather than create another reward system.

## Goals / Non-Goals

**Goals:**

- Give the companion a persisted learner-chosen name and use it consistently.
- Translate mastery state into one concrete, understandable next-unlock goal.
- Present one contextual invitation that launches an existing fixed three-question session.
- Show a brief visual pet reaction after every completed quick session.
- Make learning furniture visibly actionable while honoring reduced-motion settings.

**Non-Goals:**

- No hunger, health, decay, daily streak, virtual currency, inventory, manual room layout, network account, or notification system.
- No new question engine, grading path, progress record, or reward points for tapping pet interactions.
- No background animation that runs indefinitely.

## Decisions

1. **Store a normalized display name on the global profile.** The profile gains a non-empty `name` with a friendly default. Renaming trims whitespace, limits the visible name to eight characters, persists immediately, and does not affect species or breed selection. Existing profiles migrate through the normal tolerant JSON loader.
2. **Derive guidance instead of persisting goals.** A pure companion-guide service receives the current profile, mastery, catalog, and progress. It selects the nearest stage-locked item and computes remaining unmastered questions in the current incomplete unit. This prevents stale goal state and keeps rewards authoritative in `PetGrowthEngine`.
3. **Produce one deterministic contextual invitation.** Current mistakes select mistake-first practice. Otherwise the guide rotates among mixed, character, and read-aloud actions using completed-attempt count, accepting only actions for which the existing selector can create three attempts. The invitation contains copy, action, and a preselected session.
4. **Reuse existing launch and completion contracts.** Both mode and pet-home surfaces push `PracticePage` with the generated session. A `true` route result means all three attempts completed; early exit remains `null` and produces no completion reaction.
5. **Use ephemeral reactions, not persisted rewards.** A reusable overlay displays the named pet with a short deterministic action selected from the completed activity. It ignores pointer input, removes itself automatically, and honors reduced-motion preferences. Mastery milestone celebrations remain separate and authoritative.
6. **Furniture cues play once per room presentation.** Actionable furniture gets a short item-specific transform/glow when built. Decorative furniture stays still. Animations do not loop, play sound, or alter state, and become static affordances when animations are disabled.

## Risks / Trade-offs

- [A unit may require many remaining questions, making the next unlock feel distant] → Show the nearest incomplete lesson count when useful and phrase the unlock as a direction, not a promise after exactly one session.
- [Some invitation modes may not have three preferred attempts] → Reuse the existing compatible fallback and suppress the invitation only when no three-attempt session can be built.
- [Names may contain unusual Unicode sequences] → Enforce a small display-length limit and reject blank/control-only input without restricting family languages.
- [Motion can distract from reading] → Keep cues brief, silent, non-looping, and disable transforms when the platform requests reduced motion.
- [Two completion feedback systems can overlap] → Await milestone celebrations during grading, then show the lightweight reaction only after the quick page returns.

## Migration Plan

Existing v1-v3 profiles load with the default pet name and are saved in the new profile version after the next profile mutation or growth synchronization. Removing v5 would leave one unknown JSON field that older tolerant loaders ignore; learning records remain unchanged.

## Open Questions

Real student observation should determine the best default name, animation intensity, and invitation wording after implementation.
