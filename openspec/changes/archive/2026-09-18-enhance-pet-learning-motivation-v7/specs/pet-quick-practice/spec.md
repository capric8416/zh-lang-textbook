## MODIFIED Requirements

### Requirement: Ordinary quick completion triggers companion feedback
The system SHALL keep the named pet visibly present throughout every fixed three-question session, show at most one brief non-blocking action per graded attempt for correct answers, incorrect answers, or extended thinking, and show a completion action without granting a separate score, currency, or duplicate growth reward.

#### Scenario: Learner is still thinking
- **WHEN** a quick-practice question remains unanswered for the configured thinking interval
- **THEN** the pet shows one calm, non-judgmental thinking action without obscuring controls or changing the result

#### Scenario: An answer is graded
- **WHEN** a quick-practice answer is graded correct or incorrect
- **THEN** the pet performs the matching short action, the room may update one semantic visual cue, and the normal grading and persistence path remains unchanged

#### Scenario: Reduced motion is enabled
- **WHEN** an in-session reaction is shown while platform animations are disabled
- **THEN** the same meaning is conveyed using a static expression, color, or text

#### Scenario: Invited session completes
- **WHEN** the learner finishes all three attempts launched from a pet invitation
- **THEN** control returns to the launching surface, the pet performs one completion action, and the next goal is visible

#### Scenario: Furniture session completes
- **WHEN** the learner finishes all three attempts launched from furniture
- **THEN** pet home shows the same lightweight completion action and preserves the furniture's semantic result in addition to any mastery celebration

#### Scenario: Session exits early
- **WHEN** the learner leaves before completing all three attempts
- **THEN** no completion action is shown and existing per-attempt persistence remains unchanged
