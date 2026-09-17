## Purpose

Define the offline pet-home experience, personalization, and lightweight interactions.

## Requirements

### Requirement: Pet home shows the current companion
The system SHALL provide a dedicated pet-home screen reachable from the growth card, showing selected breed, decoration, growth points, and major stage.

#### Scenario: Open pet home
- **WHEN** the learner taps the growth card action
- **THEN** the pet-home screen opens without changing textbook state

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
