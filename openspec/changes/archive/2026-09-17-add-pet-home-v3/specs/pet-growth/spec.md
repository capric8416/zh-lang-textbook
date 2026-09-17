## MODIFIED Requirements

### Requirement: One global pet profile persists locally
The system SHALL maintain one versioned local profile shared across textbooks, initialized as dog/default, with growth points, major stages, claimed events, unlocked breed IDs, unlocked decoration IDs, selected decoration, selected room ID, and unlocked furniture IDs.

#### Scenario: First launch
- **WHEN** no profile exists
- **THEN** a zero-point default dog is created with default breed and decoration unlocked and the living room selected

#### Scenario: Legacy profile migration
- **WHEN** a v1 profile without v2 fields is loaded
- **THEN** all v1 values remain intact, default identifiers are added, and stage-derived unlocks are applied on synchronization

#### Scenario: A v2 profile is loaded
- **WHEN** a profile without room or furniture fields is loaded
- **THEN** it remains valid with the living room selected and an empty furniture set before stage normalization

### Requirement: Growth rewards cannot be farmed
The system MUST award question and lesson rewards once, grant one major stage per completed unit, and derive breed, decoration, and furniture unlocks idempotently from the resulting stage.

#### Scenario: Synchronization repeats
- **WHEN** the same practice history is synchronized again
- **THEN** rewards are not duplicated and furniture unlocks remain stable
