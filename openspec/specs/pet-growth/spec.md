## Purpose

Define the global learning companion profile, growth rewards, milestones, and visual behavior.
## Requirements
### Requirement: One global pet profile persists locally
The system SHALL maintain one versioned local profile shared across textbooks, initialized with a friendly default pet name and dog/default appearance, with growth points, major stages, claimed events, unlocked breed IDs, unlocked decoration IDs, selected decoration, selected room ID, and unlocked furniture IDs.

#### Scenario: First launch
- **WHEN** no profile exists
- **THEN** a zero-point named default dog is created with default breed and decoration unlocked and the living room selected

#### Scenario: Legacy profile migration
- **WHEN** a legacy profile without a pet name or newer customization fields is loaded
- **THEN** all existing values remain intact, a default name and default identifiers are added, and stage-derived unlocks are applied on synchronization

#### Scenario: Pet is renamed
- **WHEN** the learner submits a valid non-empty pet name within the display limit
- **THEN** the normalized name is persisted without changing learning progress, growth, breed, or rewards

### Requirement: Growth rewards cannot be farmed
The system MUST award question and lesson rewards once, grant one major stage per completed unit, derive breed, decoration, and furniture unlocks idempotently from the resulting stage, and expose newly unlocked furniture for one-time visible room feedback without awarding an additional reward.

#### Scenario: Synchronization repeats
- **WHEN** the same practice history is synchronized again
- **THEN** rewards are not duplicated, furniture unlocks remain stable, and acknowledged furniture reveals are not recreated

#### Scenario: A new furniture stage is reached
- **WHEN** synchronization first unlocks furniture for a newly completed major stage
- **THEN** the furniture is marked for one visible reveal while growth points and major-stage awards remain governed by existing claimed events

### Requirement: Existing learning history is backfilled silently
The system SHALL derive historical rewards during silent synchronization without displaying old celebrations.

#### Scenario: Mode page loads existing progress
- **WHEN** historical practice already satisfies mastery events
- **THEN** those events are persisted without celebration UI

### Requirement: Mode page presents pet growth
The system SHALL show the named current breed and decoration, growth points, major stage, textbook progress, one concrete next-unlock goal, one contextual three-question invitation, and an action opening pet home.

#### Scenario: Pet home action
- **WHEN** the learner activates the card action
- **THEN** pet home opens without changing learning progress

#### Scenario: Next unlock is available
- **WHEN** a locked breed, decoration, or furniture item remains
- **THEN** the dashboard explains the nearest learning progress that moves the pet toward that unlock

#### Scenario: Invitation is accepted
- **WHEN** the learner activates the pet's invitation
- **THEN** an available three-question session from the current textbook opens

### Requirement: Lesson milestones trigger a lower-right reaction
The system SHALL show a one-time reaction naming the current pet for newly reached lesson milestones, using increasingly rare expressions for 80%, 90%, and 100%.

#### Scenario: Multiple thresholds
- **WHEN** one result crosses multiple thresholds
- **THEN** all events are claimed and one named-pet reaction uses the highest threshold

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
