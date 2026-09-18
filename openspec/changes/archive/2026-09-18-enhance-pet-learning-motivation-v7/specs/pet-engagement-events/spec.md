## MODIFIED Requirements

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
