## MODIFIED Requirements

### Requirement: One global default dog profile persists locally
The system SHALL maintain one versioned local pet profile shared across textbooks, initialized as species `dog` and breed `default`, with total growth points, completed major stages, claimed event keys, unlocked breed IDs, unlocked decoration IDs, and the selected decoration.

#### Scenario: First launch initializes a dog
- **WHEN** no pet profile has been stored
- **THEN** the system creates a default dog with zero growth points, zero completed major stages, the default breed unlocked, and no locked selection state

#### Scenario: App restarts preserve growth and personalization
- **WHEN** the app restarts after growth or pet-home selections have been saved
- **THEN** the same growth points, stages, claimed events, selected breed, and selected decoration are restored

#### Scenario: A v1 profile is loaded
- **WHEN** a profile without v2 fields is loaded
- **THEN** it remains valid, retains all v1 values, and receives stage-derived unlocks with the default breed as a safe fallback

### Requirement: Growth rewards cannot be farmed
The system MUST award growth points once per stable mastery event, MUST grant one major growth stage once per completed unit, and MUST derive breed and decoration unlocks idempotently from the resulting major stage.

#### Scenario: Synchronization reaches a new stage
- **WHEN** an unclaimed unit-completion event advances the profile to a new major stage
- **THEN** the profile gains that stage's configured unlocks exactly once without changing the reward totals

#### Scenario: Synchronization is repeated
- **WHEN** the same practice history is synchronized again
- **THEN** no reward is duplicated and the unlock sets remain unchanged

### Requirement: Mode page presents pet growth
The system SHALL show a compact pet card containing the current breed and decoration, total growth points, completed major-stage count, selected-textbook progress, and an action that opens pet home.

#### Scenario: Learner opens pet home from mode page
- **WHEN** the learner activates the card action
- **THEN** pet home opens with the same profile and textbook context

### Requirement: Pet visuals are accessible and extensible
The system SHALL render catalog breeds and decorations through the reusable appearance and expression interface, SHALL play no automatic sound, and SHALL reduce motion when the platform requests disabled animations.

#### Scenario: Future breed is added
- **WHEN** a later version registers another catalog descriptor
- **THEN** existing profile persistence and growth synchronization continue without a schema change
