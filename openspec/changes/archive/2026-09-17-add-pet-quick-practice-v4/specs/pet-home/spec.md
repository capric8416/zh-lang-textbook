## MODIFIED Requirements

### Requirement: Learning-earned furniture is selectable by room
The system SHALL expose a small catalog of furniture associated with rooms, unlock furniture deterministically by major stage, place unlocked furniture in fixed slots without requiring manual layout editing, and make configured furniture accessible as current-textbook learning entry points.

#### Scenario: Furniture unlocks
- **WHEN** silent growth synchronization observes a newly reached major stage
- **THEN** that stage's furniture becomes available in its configured room without granting extra growth points

#### Scenario: Furniture layout is automatic
- **WHEN** a room is displayed
- **THEN** all unlocked furniture for that room appears in stable predefined positions

#### Scenario: Learning furniture is activated
- **WHEN** the learner taps an unlocked furniture item configured for learning
- **THEN** it opens its standard-practice action or a fixed three-question activity using only the current textbook

#### Scenario: Decorative furniture is activated
- **WHEN** the learner taps furniture without a learning action
- **THEN** it remains decorative and does not alter progress or rewards
