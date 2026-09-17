## Purpose

Define the global learning companion profile, growth rewards, milestones, and visual behavior.

## Requirements

### Requirement: One global pet profile persists locally
The system SHALL maintain one versioned local profile shared across textbooks, initialized as dog/default, with growth points, major stages, claimed events, unlocked breed IDs, unlocked decoration IDs, and selected decoration.

#### Scenario: First launch
- **WHEN** no profile exists
- **THEN** a zero-point default dog is created with default breed and decoration unlocked

#### Scenario: Legacy profile migration
- **WHEN** a v1 profile without v2 fields is loaded
- **THEN** all v1 values remain intact, default identifiers are added, and stage-derived unlocks are applied on synchronization

### Requirement: Growth rewards cannot be farmed
The system MUST award question and lesson rewards once, grant one major stage per completed unit, and derive breed/decor unlocks idempotently from the resulting stage.

#### Scenario: Repeated synchronization
- **WHEN** the same practice history is synchronized again
- **THEN** rewards are not duplicated and unlock sets remain stable

### Requirement: Existing learning history is backfilled silently
The system SHALL derive historical rewards during silent synchronization without displaying old celebrations.

#### Scenario: Mode page loads existing progress
- **WHEN** historical practice already satisfies mastery events
- **THEN** those events are persisted without celebration UI

### Requirement: Mode page presents pet growth
The system SHALL show the current breed and decoration, growth points, major stage, textbook progress, and an action opening pet home.

#### Scenario: Pet home action
- **WHEN** the learner activates the card action
- **THEN** pet home opens without changing learning progress

### Requirement: Lesson milestones trigger a lower-right reaction
The system SHALL show a one-time reaction for newly reached lesson milestones, using increasingly rare expressions for 80%, 90%, and 100%.

#### Scenario: Multiple thresholds
- **WHEN** one result crosses multiple thresholds
- **THEN** all events are claimed and one reaction uses the highest threshold

### Requirement: Unit completion triggers full-screen celebration
The system SHALL show one full-screen confetti celebration when a unit first completes and SHALL not replay it on revisits.

#### Scenario: Completed unit revisited
- **WHEN** a claimed unit is practiced again
- **THEN** no new unit celebration is shown

### Requirement: Pet visuals are accessible and extensible
The system SHALL render catalog breeds and decorations through a reusable interface, play no automatic sound, and reduce motion when requested by the platform.

#### Scenario: Future catalog entry
- **WHEN** a new dog or cat descriptor is registered
- **THEN** persistence and growth synchronization continue without a schema change
