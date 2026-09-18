## MODIFIED Requirements

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

## ADDED Requirements

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
