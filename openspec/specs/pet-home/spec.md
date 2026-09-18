## Purpose

Define the offline pet-home experience, personalization, and lightweight interactions.
## Requirements
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
The system SHALL expose a small catalog of furniture associated with rooms, unlock furniture deterministically by major stage, place unlocked furniture in fixed slots without requiring manual layout editing, make configured furniture accessible as current-textbook learning entry points, visually distinguish actionable furniture with brief motion-aware cues, and render persistent semantic states earned through unlocks and completed missions.

#### Scenario: Furniture unlocks
- **WHEN** silent growth synchronization observes a newly reached major stage
- **THEN** that stage's furniture becomes available in its configured room with a one-time reveal marker and without granting extra growth points

#### Scenario: Furniture layout is automatic
- **WHEN** a room is displayed
- **THEN** all unlocked furniture for that room appears in stable predefined positions

#### Scenario: Newly unlocked furniture is revealed
- **WHEN** pet home first displays an unacknowledged furniture unlock and animations are enabled
- **THEN** the room shows one brief reveal and persists that the reveal has been seen

#### Scenario: Mission changes furniture state
- **WHEN** a three-question furniture mission completes
- **THEN** the target furniture persists and displays its active semantic variant, such as a glowing lamp, stocked bookcase, or blooming flower pot

#### Scenario: Learning furniture is presented
- **WHEN** an actionable furniture item appears and animations are enabled
- **THEN** it performs one brief item-appropriate cue and remains clearly actionable afterward

#### Scenario: Reduced motion is enabled
- **WHEN** an actionable or newly unlocked furniture item appears while platform animations are disabled
- **THEN** its active or actionable state remains visible without animated transforms

#### Scenario: Learning furniture is activated
- **WHEN** the learner taps an unlocked furniture item configured for learning
- **THEN** it opens its standard-practice action or a fixed three-question activity using only the current textbook

#### Scenario: Decorative furniture is activated
- **WHEN** the learner taps furniture without a learning action
- **THEN** it remains decorative and does not alter progress or rewards

### Requirement: Pet home varies daily without pressure
The system SHALL choose a stable daily pet position and friendly greeting from anonymous installation, local date, selected room, and recent activity category without creating a reward or obligation.

#### Scenario: Learner returns the next day
- **WHEN** pet home or the mode-page companion is first opened on the calendar day after the previous companion visit
- **THEN** the pet appears in the day's stable valid position, may reference the last activity category, and records a next-day return

#### Scenario: Learner returns after a longer absence
- **WHEN** multiple calendar days have elapsed since the previous companion visit
- **THEN** the pet gives a neutral friendly greeting without mentioning missed days, loss, hunger, or disappointment

#### Scenario: Learner revisits on the same day
- **WHEN** the same room is reopened on the same local date
- **THEN** the pet position remains stable and no duplicate next-day return is recorded

### Requirement: Companion offers a contextual lightweight task
The system SHALL present at most one named-pet invitation per local cooldown window, derive it from the current textbook's useful learning gap and current unit, allow it to be skipped without penalty, and launch it through the existing quick-practice selector.

#### Scenario: Current mistakes exist
- **WHEN** the learner has current mistakes and opens a companion surface within the invitation allowance
- **THEN** the invitation prioritizes a three-question mistake activity and previews the associated room result

#### Scenario: An unfinished unit goal exists
- **WHEN** no higher-priority mistake activity is available and the current unit has an unfinished goal
- **THEN** the invitation offers the smallest useful action for that goal using only the current textbook

#### Scenario: Invitation is skipped
- **WHEN** the learner dismisses the invitation
- **THEN** the invitation is not shown again during the same cooldown window and no growth, streak, or room state is changed

#### Scenario: Invitation is accepted
- **WHEN** the learner accepts the invitation
- **THEN** the selected three-question session starts, the room mission is attached, and the scheduler applies its acceptance cooldown

#### Scenario: No current work is available
- **WHEN** no current mistakes, unfinished goal, or compatible attempts exist
- **THEN** no invitation is presented and the pet home remains usable for ordinary navigation

