## MODIFIED Requirements

### Requirement: Pet home shows the current companion
The system SHALL provide a dedicated pet-home screen reachable from the growth card, showing the selected breed, decoration, growth points, major stage, switchable rooms, and automatically placed furniture.

#### Scenario: Open pet home
- **WHEN** the learner taps the growth card action
- **THEN** the pet-home screen opens without changing textbook state and shows the last selected room

#### Scenario: Switch rooms
- **WHEN** the learner taps another unlocked room tab
- **THEN** the corresponding room theme and furniture layout are shown immediately and the selected room is persisted

## ADDED Requirements

### Requirement: Learning-earned furniture is selectable by room
The system SHALL expose a small catalog of furniture associated with rooms, unlock furniture deterministically by major stage, and place unlocked furniture in fixed slots without requiring manual layout editing.

#### Scenario: Furniture unlocks
- **WHEN** silent growth synchronization observes a newly reached major stage
- **THEN** that stage's furniture becomes available in its configured room without granting extra growth points

#### Scenario: Furniture layout is automatic
- **WHEN** a room is displayed
- **THEN** all unlocked furniture for that room appears in stable predefined positions
