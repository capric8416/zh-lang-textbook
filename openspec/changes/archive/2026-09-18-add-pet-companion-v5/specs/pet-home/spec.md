## MODIFIED Requirements

### Requirement: Pet home shows the current companion
The system SHALL provide a dedicated pet-home screen reachable from the growth card, showing and allowing rename of the selected companion, its breed, decoration, growth points, major stage, next-unlock goal, contextual learning invitation, switchable rooms, and automatically placed furniture.

#### Scenario: Open pet home
- **WHEN** the learner taps the growth card action
- **THEN** the pet-home screen opens without changing textbook state and shows the named pet, current guidance, and last selected room

#### Scenario: Rename pet
- **WHEN** the learner chooses rename and submits a valid name
- **THEN** the pet home immediately displays and persists the new name

#### Scenario: Switch rooms
- **WHEN** the learner taps another unlocked room tab
- **THEN** the corresponding room theme and furniture layout are shown immediately and the selected room is persisted

### Requirement: Learning-earned furniture is selectable by room
The system SHALL expose a small catalog of furniture associated with rooms, unlock furniture deterministically by major stage, place unlocked furniture in fixed slots without requiring manual layout editing, make configured furniture accessible as current-textbook learning entry points, and visually distinguish actionable furniture with brief motion-aware cues.

#### Scenario: Furniture unlocks
- **WHEN** silent growth synchronization observes a newly reached major stage
- **THEN** that stage's furniture becomes available in its configured room without granting extra growth points

#### Scenario: Furniture layout is automatic
- **WHEN** a room is displayed
- **THEN** all unlocked furniture for that room appears in stable predefined positions

#### Scenario: Learning furniture is presented
- **WHEN** an actionable furniture item appears and animations are enabled
- **THEN** it performs one brief item-appropriate cue and remains clearly actionable afterward

#### Scenario: Reduced motion is enabled
- **WHEN** an actionable furniture item appears while platform animations are disabled
- **THEN** it remains visibly actionable without animated transforms

#### Scenario: Learning furniture is activated
- **WHEN** the learner taps an unlocked furniture item configured for learning
- **THEN** it opens its standard-practice action or a fixed three-question activity using only the current textbook

#### Scenario: Decorative furniture is activated
- **WHEN** the learner taps furniture without a learning action
- **THEN** it remains decorative and does not alter progress or rewards

## ADDED Requirements

### Requirement: Companion offers a contextual lightweight task
The system SHALL present one named-pet invitation derived from current-textbook progress and launch it through the existing quick-practice selector.

#### Scenario: Current mistakes exist
- **WHEN** the learner has current mistakes and opens a companion surface
- **THEN** the invitation prioritizes a three-question mistake activity

#### Scenario: No current mistakes exist
- **WHEN** no current mistakes exist and at least three compatible attempts are available
- **THEN** the invitation offers an available mixed, character, or read-aloud three-question activity
