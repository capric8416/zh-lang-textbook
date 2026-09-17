## Purpose

Define the offline pet-home experience, personalization, and lightweight interactions.
## Requirements
### Requirement: Pet home shows the current companion
The system SHALL provide a dedicated pet-home screen reachable from the growth card, showing the selected breed, decoration, growth points, major stage, switchable rooms, and automatically placed furniture.

#### Scenario: Open pet home
- **WHEN** the learner taps the growth card action
- **THEN** the pet-home screen opens without changing textbook state and shows the last selected room

#### Scenario: Switch rooms
- **WHEN** the learner taps another unlocked room tab
- **THEN** the corresponding room theme and furniture layout are shown immediately and the selected room is persisted

### Requirement: Unlocked breeds can be selected
The system SHALL show dog and cat catalog entries, indicate locked entries and required stage, and allow selecting only unlocked breeds.

#### Scenario: Select breed
- **WHEN** an unlocked breed is tapped
- **THEN** it is persisted and the preview updates

### Requirement: Learning-earned decorations are selectable
The system SHALL expose deterministic collars, scarves, and backgrounds unlocked by growth and preserve the selected decoration across restarts.

#### Scenario: Select decoration
- **WHEN** an unlocked decoration is tapped
- **THEN** it is persisted and rendered by the preview

### Requirement: Interactions are lightweight and non-competitive
The system SHALL provide petting, greeting, and tail-wagging feedback without cost, cooldown penalty, hunger, decay, score, or learning impact.

#### Scenario: Interaction
- **WHEN** an interaction control is tapped
- **THEN** brief local feedback is shown and learning data remains unchanged

#### Scenario: Reduced motion
- **WHEN** disabled animations are requested
- **THEN** feedback is static or immediate

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
