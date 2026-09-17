## Context

Practice progress is already persisted per textbook and per question direction through `PracticeProgressStore`. The catalog maps questions to textbook chapters, but there is no higher-level mastery model, global learner profile, or durable event ledger. The new pet loop must work offline, migrate existing learning history without an animation storm, remain deterministic across restarts, and avoid introducing a game economy that competes with learning.

## Goals / Non-Goals

**Goals:**

- Derive monotonic lesson and unit mastery from existing practice records.
- Award global dog growth exactly once for first mastery and threshold events.
- Present a default dog, lesson reactions, and unit confetti without external animation dependencies.
- Backfill growth from existing progress silently and preserve future breed extensibility.
- Keep practice, OCR, speech, and mistake-remediation behavior unchanged.

**Non-Goals:**

- Badges, maps, shops, consumable currency, feeding, hunger, decay, streak punishment, or multiple active pets.
- Cloud sync or cross-device identity.
- A separate game screen or free-form pet interaction loop.
- Unique artwork for every unit or breed in v1.

## Decisions

### Mastery uses unique catalog questions

A question is mastered for lesson-completion purposes when any currently supported practice direction has at least one correct attempt. Repeating a mastered question does not increase mastery. A lesson percentage is `mastered unique questions / eligible unique questions`; comparison uses integer arithmetic so thresholds are stable.

This is preferred over counting attempts or requiring every practice direction. Attempt counts encourage farming, while requiring all directions makes normal progression too heavy for younger learners. Wrong answers continue to participate in the existing mistake-practice rules but never revoke historical mastery.

### Units require every eligible lesson to pass

A lesson passes at 60%. A unit completes only when every chapter containing at least one eligible practice question reaches 60%. Chapters without catalog questions are excluded rather than making a unit impossible to complete. Appendix content is not treated as a unit.

This prevents a strong result in one lesson from hiding an untouched lesson.

### Rewards are derived and claimed through an idempotent ledger

`PetGrowthStore` uses one global SharedPreferences record with a versioned profile and sets of claimed event keys. A synchronization service compares a textbook catalog and `PracticeProgress` with the claimed ledger. Newly claimable events update growth points and return celebration events in one save.

Event keys include the textbook file name and stable question, chapter, or unit IDs. Initial synchronization on the mode page backfills old learning history silently: it awards points and marks historical milestones claimed but emits no animations. Synchronization immediately after a newly recorded answer emits only events caused by that answer.

V1 growth values are:

- Unique question first mastered: 10 points.
- Lesson 60% milestone: 30 points.
- Lesson 80% milestone: 20 points.
- Lesson 90% milestone: 20 points.
- Lesson 100% milestone: 30 points.
- Unit completion: 100 points and one major growth stage.

If one answer crosses several lesson thresholds, all rewards are claimed but only the highest crossed lesson reaction is animated. If it also completes a unit, the lesson reaction runs first and the full-screen unit celebration follows.

### Pet identity is global; curriculum mastery remains per textbook

The profile contains a stable `species`, `breed`, total growth points, and completed-unit count. V1 initializes `species=dog` and `breed=default`. Textbook-specific IDs remain part of mastery and event keys, allowing the same dog to continue growing across grades without merging unrelated lesson progress.

### Visuals are code-rendered and dependency-free

A reusable `PetAvatar` uses `CustomPainter` with a pet appearance descriptor and expression enum. V1 renders one friendly dog; later breed descriptors can change coat palette, ear shape, markings, and proportions without changing persistence or milestone logic.

Lesson celebrations use Flutter animation controllers to slide/run the dog through the lower-right area, with threshold-specific expressions and aura colors. Unit celebrations use a full-screen overlay and a deterministic custom confetti painter. Animations respect `MediaQuery.disableAnimations`; reduced-motion mode shows a brief static reaction instead. No sound plays automatically.

### UI integration stays close to learning

The mode page adds a compact dog card showing total growth points, major stage count, and progress toward the next incomplete lesson in the selected textbook. Practice pages invoke the synchronization service after a successful grading record and enqueue any returned celebrations. The pet never covers the writing or answer controls when idle.

## Risks / Trade-offs

- **Existing users may receive substantial backfilled growth** → Backfill silently and show the resulting level only, without replaying old celebrations.
- **Some textbook chapters have few or no generated questions** → Exclude empty chapters and show exact mastered/total counts in the pet card.
- **A single correct direction may feel too permissive later** → Keep mastery calculation isolated so a future version can add direction-specific goals without changing stored practice records.
- **Custom-painted art is less detailed than authored animation assets** → Favor a coherent, responsive v1 mascot and keep an appearance abstraction ready for later breed assets.
- **Large overlays may distract or affect accessibility** → Play each event once, omit sound, serialize animations, and honor reduced-motion settings.

## Migration Plan

1. Add the independent versioned pet store; do not modify existing practice-progress JSON.
2. On first mode-page load, derive and silently claim historical rewards from the selected textbook.
3. After each future grading record, derive and emit only newly crossed events.
4. A rollback can remove the pet UI and service calls while leaving the isolated pet preference record harmlessly unused.

## Open Questions

None for v1. Reward values and visual timing are implementation constants that can be tuned without changing the persistence contract.
