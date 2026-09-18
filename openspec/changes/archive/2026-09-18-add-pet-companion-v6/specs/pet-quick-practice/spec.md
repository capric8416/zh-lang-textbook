## MODIFIED Requirements

### Requirement: Ordinary quick completion triggers companion feedback
The system SHALL keep the named pet visibly present throughout every fixed three-question session, show brief non-blocking reactions to correct answers, incorrect answers, and extended thinking, and show a completion reaction without granting a separate score, currency, or duplicate growth reward.

#### Scenario: Learner is still thinking
- **WHEN** a quick-practice question remains unanswered for the configured thinking interval
- **THEN** the pet shows one calm, non-judgmental thinking reaction without obscuring controls or changing the result

#### Scenario: An answer is graded
- **WHEN** a quick-practice answer is graded correct or incorrect
- **THEN** the pet briefly celebrates or encourages and the normal grading and persistence path remains unchanged

#### Scenario: Reduced motion is enabled
- **WHEN** an in-session reaction is shown while platform animations are disabled
- **THEN** the same meaning is conveyed using a static expression and text

#### Scenario: Invited session completes
- **WHEN** the learner finishes all three attempts launched from a pet invitation
- **THEN** control returns to the launching surface and the pet performs a short activity-appropriate reaction

#### Scenario: Furniture session completes
- **WHEN** the learner finishes all three attempts launched from furniture
- **THEN** pet home shows the same lightweight completion reaction in addition to any already-earned mastery celebration

#### Scenario: Session exits early
- **WHEN** the learner leaves before completing all three attempts
- **THEN** no completion reaction is shown and existing per-attempt persistence remains unchanged

## ADDED Requirements

### Requirement: Quick practice presents a three-step room mission
The system SHALL derive a named-pet room mission from the quick-practice action and launch source, present one mission step per answered attempt, and reuse the existing three-question selection, grading, and progress records.

#### Scenario: A furniture mission starts
- **WHEN** quick practice is launched from an actionable furniture item
- **THEN** the introduction names that furniture and previews a three-step visual outcome appropriate to it

#### Scenario: An invited mission starts
- **WHEN** quick practice is launched from a general pet invitation
- **THEN** an available room mission is selected without changing the three selected attempts

#### Scenario: An answer is incorrect
- **WHEN** one of the three attempts is completed incorrectly
- **THEN** the mission advances, the pet encourages the learner, and the room outcome is not withheld

### Requirement: Completed quick practice offers voluntary repetition
The system SHALL offer a clearly optional action to start another suitable three-question session after completion and SHALL treat dismissal as a normal end state.

#### Scenario: Learner chooses another session
- **WHEN** the learner activates the repeat action after completing three attempts
- **THEN** a new session is selected from the current textbook and recorded as a voluntary repeat start

#### Scenario: Learner dismisses completion
- **WHEN** the learner returns to the prior screen without repeating
- **THEN** no loss, warning, streak break, or pet disappointment is shown
