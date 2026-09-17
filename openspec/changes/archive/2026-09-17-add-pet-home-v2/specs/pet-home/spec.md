## ADDED Requirements

### Requirement: Pet home is reachable and shows current companion
The system SHALL provide a dedicated pet-home screen reachable from the mode-page pet growth card, showing the selected breed, current decoration, growth points, and major stage.

#### Scenario: Learner opens pet home
- **WHEN** the learner taps the pet growth card action
- **THEN** the pet-home screen opens without changing textbook or practice state

### Requirement: Unlocked breeds can be selected
The system SHALL show the catalog of dog and cat breeds, indicate locked entries, and allow selection only for breeds unlocked by the learner's major growth stage.

#### Scenario: Learner selects an unlocked breed
- **WHEN** the learner taps an unlocked breed
- **THEN** the profile stores that breed and the pet preview updates immediately

#### Scenario: Learner taps a locked breed
- **WHEN** the learner taps a breed whose unlock stage is not reached
- **THEN** the selection remains unchanged and the screen explains the required growth stage

### Requirement: Learning-earned decorations are selectable
The system SHALL expose deterministic collars, scarves, and simple backgrounds unlocked by learning growth, and SHALL preserve the selected decoration across restarts.

#### Scenario: Decoration unlocks at a new stage
- **WHEN** silent growth synchronization observes a newly reached major stage
- **THEN** the corresponding decoration becomes available without granting extra growth points

#### Scenario: Learner selects an unlocked decoration
- **WHEN** the learner taps an unlocked decoration
- **THEN** the profile stores it and the pet preview renders it

### Requirement: Interactions are lightweight and non-competitive
The system SHALL provide tap-triggered interactions such as petting, greeting, and tail-wagging that have short visual feedback and no cost, cooldown penalty, hunger, decay, or score effect.

#### Scenario: Learner taps an interaction
- **WHEN** the learner taps an interaction control
- **THEN** the pet plays its brief local feedback and learning data remains unchanged

#### Scenario: Reduced motion is enabled
- **WHEN** the platform requests disabled animations
- **THEN** the interaction displays a brief static response without motion
