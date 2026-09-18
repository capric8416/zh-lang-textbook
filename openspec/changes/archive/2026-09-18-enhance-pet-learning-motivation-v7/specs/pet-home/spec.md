## MODIFIED Requirements

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
