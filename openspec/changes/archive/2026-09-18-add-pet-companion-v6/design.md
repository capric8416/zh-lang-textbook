## Context

V5 connects a named pet to learning goals, three-question invitations, furniture entry points, and brief completion reactions. During the actual three-question session the pet is absent, furniture unlocks are mostly catalog changes, and there is no evidence trail for determining whether invitations increase voluntary practice. The app is offline-first, stores progress locally, supports reduced motion, and must not turn the pet into a punitive dependency.

This change crosses practice presentation, pet-home state, persistence, and product measurement. It therefore introduces a small companion-session model and a versioned local engagement log, while preserving the existing question, mastery, mistake, and growth systems as the learning source of truth.

## Goals / Non-Goals

**Goals:**

- Make the pet visibly present but non-blocking throughout fixed three-question practice.
- Convert three-question activities into short room missions with gentle, answer-aware reactions.
- Make furniture unlocks and mission completion produce persistent, visible room changes.
- Add varied daily greetings and positions without streaks, missed-day messages, or degradation.
- Store a privacy-conscious event log that can later be mapped to protobuf and sent over gRPC.
- Derive invitation click-through, quick completion, voluntary repeat, and next-day return measures from that log.

**Non-Goals:**

- No gRPC client, `.proto` contract, endpoint, authentication, background transfer, or remote dashboard in this change.
- No currency, daily reward, streak, hunger, health, decay, punishment, leaderboard, or notification.
- No logging of answer text, recognized speech, audio, pet names, free-form user input, or direct student identity.
- No replacement of normal progress, mistake, mastery, or pet-growth records.
- No large animation or game-engine dependency.

## Decisions

### Use one companion mission model for every fixed three-question session

`PetCompanionMission` is derived before navigation from the quick-practice action, launch source, selected room, and optional furniture ID. It contains a stable mission kind, child-facing intro/completion copy, furniture target, and three presentation steps. The existing `QuickPracticeSession` remains responsible for exactly which questions are attempted.

Each answered item advances the mission presentation, regardless of correctness. Correctness only selects a brief pet reaction (`celebrate` or `encourage`), so a child is never denied the room outcome after finishing the promised three questions. This favors completion and emotional safety over using furniture as another grading layer.

Alternative considered: advance the mission only for correct answers. Rejected because it silently changes “three-question practice” into an additional pass condition and could turn the pet into a source of disappointment.

### Keep companion reactions transient and presentation-only

The practice page owns a small state machine for quick sessions:

```
idle ──10s──> thinking
  │             │
  └──graded─────┴──> celebrate | encourage ──brief delay──> idle
```

The thinking threshold is reset on every question. The overlay never covers the answer control, never changes grading, and becomes static text/expression when reduced motion is enabled. No per-question reaction or correctness is written to the engagement log.

Alternative considered: persist pet mood between sessions. Rejected for this phase because it adds ambiguous emotional state and risks making mistakes feel harmful to the pet.

### Persist semantic furniture state, not animation frames or scores

Pet companion state stores a map from furniture ID to a semantic variant such as `default`, `ready`, or `active`, plus the last newly unlocked furniture IDs awaiting a one-time reveal. Renderers map those variants to concrete visuals: the lamp glows, the bookcase gains books, and the flower pot blooms. Mission steps can preview intermediate changes in practice, while successful three-question completion commits the final semantic state.

Unlock synchronization remains idempotent. A newly unlocked item receives its initial reveal once; repeated synchronization does not replay it. This adds visible consequences without creating a separate furniture-level economy.

Alternative considered: store a numeric level for every furniture item. Rejected because it encourages another progression system and couples storage to visual details.

### Derive daily variation deterministically and store only visit continuity

The pet position and greeting variant are selected from `(anonymousInstallId, localDate, roomId)` so they remain stable for a day without growing storage. A small companion visit record stores the last local visit date and last completed mission kind. Greetings may reference the last activity category but never correctness or missed days. A next-day return is recognized only when the prior local date is exactly the preceding calendar day; longer gaps receive the same friendly neutral greeting.

Alternative considered: daily rewards or streak counters. Rejected because they create pressure and contradict the non-punitive companion model.

### Store immutable versioned engagement events behind a repository

Producers call an `EngagementEventStore` interface rather than SharedPreferences directly. Each immutable event uses a transport-friendly envelope:

```
eventId             opaque 128-bit identifier
schemaVersion       integer
eventType           closed enum
occurredAtUtc       ISO-8601 UTC timestamp
localDate           YYYY-MM-DD for return derivation
anonymousInstallId  random local opaque identifier
sessionId           random identifier for one app process/session
sequence            monotonically increasing local integer
context             typed fields, no arbitrary free-form map
deliveryState       pending | acknowledged
attemptCount        upload metadata, initially zero
```

Typed context fields are optional and enumerated: textbook key, surface, launch source, quick-practice action, mission kind, room ID, furniture ID, and bounded duration bucket. Event types for this phase are `companionSurfaceViewed`, `invitationPresented`, `quickPracticeStarted`, `quickPracticeExited`, `quickPracticeCompleted`, `repeatPracticeStarted`, and `nextDayReturn`.

The initial SharedPreferences-backed implementation stores a bounded JSON outbox in append order. It retains at most 1,000 events and at most 90 days, pruning acknowledged events before pending events. Because no uploader exists yet, records remain pending; the delivery fields establish a migration-safe boundary for a future database/protobuf adapter. Corrupt individual records are skipped without blocking learning.

Alternative considered: aggregate counters only. Rejected because funnels, deduplication, retry, schema migration, and later gRPC delivery cannot be reconstructed reliably. SQLite was also considered but deferred because the bounded first-phase volume does not justify a new native dependency.

### Define metrics as pure projections over events

Metrics are calculated rather than independently incremented:

- invitation click-through = unique invitation starts / unique invitation presentations;
- quick completion = completed quick sessions / started quick sessions;
- voluntary repeat = repeat starts / completed quick sessions that displayed a repeat action;
- next-day return = anonymous installs with a next-day-return event / eligible installs with a prior-day companion visit.

Event IDs and session IDs prevent duplicate UI rebuilds or repeated calculation from inflating counts. The local diagnostics view or tests may inspect projections, but no child-facing score is created.

## Risks / Trade-offs

- **[SharedPreferences rewrites the bounded event array]** → Cap retention at 1,000 events, prune on append, isolate persistence behind a repository, and migrate to a database when upload is implemented.
- **[UI rebuilds duplicate impression events]** → Give each surface lifecycle a stable presentation ID and record each event ID once.
- **[Thinking animation distracts or shames slow learners]** → Use calm “慢慢想” feedback, trigger only once per question, keep controls unobscured, and honor reduced motion.
- **[Furniture mission implies correctness is required]** → Advance mission visuals on completed attempts and keep correctness limited to transient encouragement.
- **[Local dates change through timezone or clock edits]** → Store both UTC time and local date; treat ambiguous or backward dates as neutral visits rather than returns.
- **[Future protobuf fields diverge from local JSON]** → Keep a closed event enum, explicit schema version, typed context, and a mapping boundary instead of exposing stored JSON to producers.
- **[Analytics captures excessive learning data]** → Use an allowlist of fields, exclude all answer/audio/free-form values, cap duration precision, and test serialization for prohibited fields.

## Migration Plan

1. Add the companion-state and engagement-event models with tolerant decoding and new local keys; existing pet profiles remain valid.
2. Introduce the repository and pure metric projector before instrumenting UI call sites.
3. Add mission derivation and in-practice companion presentation behind the existing `quickSession != null` branch.
4. Add semantic furniture variants and one-time unlock reveals, migrating unlocked legacy furniture to `ready` without replaying historical celebrations.
5. Add daily visit state and then instrument invitation, session, repeat, completion, exit, and return events.
6. Rollback can stop reading the new keys; existing learning and pet-growth data are independent and remain intact.

## Open Questions

- The eventual server retention period, consent flow, endpoint authentication, and protobuf package/version will be defined with the gRPC upload change.
- Before remote upload, decide whether textbook key should be sent verbatim, mapped to a catalog ID, or reduced to grade/volume fields.
- Validate the ten-second thinking threshold and wording with a small primary-school usability session before treating them as stable product defaults.
