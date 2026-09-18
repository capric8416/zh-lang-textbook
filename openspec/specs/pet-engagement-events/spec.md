## Purpose

Define privacy-preserving local engagement events, bounded offline delivery storage, and derived companion-learning metrics for future transport integration.
## Requirements
### Requirement: Engagement events use a stable privacy-preserving envelope
The system SHALL append immutable, schema-versioned engagement events with a unique event ID, UTC timestamp, local date, anonymous installation ID, session ID, monotonic local sequence, closed event type, typed optional context, and delivery metadata; the closed event type SHALL include invitation presentation, invitation acceptance, invitation skip, goal viewed, and goal-driven practice start.

#### Scenario: An invitation is started
- **WHEN** the learner accepts a presented pet invitation
- **THEN** one quick-practice-started event records the invitation source and typed activity context without answer content, audio, pet name, or direct student identity

#### Scenario: An invitation is skipped
- **WHEN** the learner dismisses a presented invitation
- **THEN** one invitation-skipped event records the surface and local session context without free-form reason text

#### Scenario: A goal is viewed
- **WHEN** a goal card becomes visible for the presentation lifecycle
- **THEN** one goal-viewed event records the goal kind and textbook/room identifiers without answer content or student identity

#### Scenario: A producer attempts to attach free-form data
- **WHEN** an engagement event is constructed
- **THEN** only allowlisted typed context fields can be serialized

### Requirement: Engagement events form a bounded future upload outbox
The system SHALL persist engagement events locally in append order behind a repository, mark new records pending, retain no more than 1,000 events or 90 days, and keep delivery state separate from immutable event content.

#### Scenario: Retention limit is exceeded
- **WHEN** appending an event would exceed a retention boundary
- **THEN** acknowledged records are pruned before the oldest pending records without affecting learning or pet state

#### Scenario: A stored record is corrupt
- **WHEN** the local event store contains one undecodable record
- **THEN** that record is skipped and new engagement events can still be appended

#### Scenario: No uploader exists
- **WHEN** this version records an event
- **THEN** it remains pending and no network request is attempted

### Requirement: Engagement metrics are derived from logged events
The system SHALL derive invitation click-through, quick-session completion, voluntary repeat, and next-day return measures from deduplicated engagement events rather than maintaining a second mutable counter store.

#### Scenario: A UI rebuild repeats an impression callback
- **WHEN** the same presentation event ID is appended more than once
- **THEN** it contributes at most once to the derived invitation denominator

#### Scenario: A quick session is exited early
- **WHEN** a started session records an exit without completion
- **THEN** it remains in the completion denominator and not the completion numerator

#### Scenario: A next-day visit occurs
- **WHEN** a companion surface is visited on the calendar day immediately after its previous local visit
- **THEN** one next-day-return event is available to the return projection

### Requirement: Event records are transport-ready but remain offline
The system SHALL expose event models through an adapter boundary suitable for later protobuf mapping while excluding gRPC transport, authentication, background upload, and remote deletion behavior from this version.

#### Scenario: Events are recorded offline
- **WHEN** the device has no network connection
- **THEN** event capture and all learning behavior operate normally without network errors or delays

