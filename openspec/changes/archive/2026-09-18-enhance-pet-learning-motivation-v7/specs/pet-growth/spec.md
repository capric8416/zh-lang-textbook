## MODIFIED Requirements

### Requirement: Mode page presents pet growth
The system SHALL show the named current breed and decoration, growth points, major stage, textbook progress, one concrete next-unlock goal, one current-textbook learning goal with remaining actionable amount, one contextual three-question invitation subject to local frequency limits, and an action opening pet home.

#### Scenario: Pet home action
- **WHEN** the learner activates the card action
- **THEN** pet home opens without changing learning progress

#### Scenario: Next unlock is available
- **WHEN** a locked breed, decoration, or furniture item remains
- **THEN** the dashboard explains the nearest learning progress that moves the pet toward that unlock

#### Scenario: Learning goal is available
- **WHEN** the current textbook has an incomplete goal
- **THEN** the dashboard shows its progress, remaining amount, action label, and associated room outcome

#### Scenario: Invitation is accepted
- **WHEN** the learner activates the pet's invitation within its local frequency allowance
- **THEN** an available three-question session from the current textbook opens and the invitation is recorded as accepted

#### Scenario: Invitation is suppressed
- **WHEN** the learner already saw or skipped the daily invitation, or no useful goal exists
- **THEN** no new invitation is shown and the normal growth card remains usable
