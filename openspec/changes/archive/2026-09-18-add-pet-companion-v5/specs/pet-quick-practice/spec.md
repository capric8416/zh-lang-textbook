## ADDED Requirements

### Requirement: Ordinary quick completion triggers companion feedback
The system SHALL show a brief named-pet visual reaction after any fixed three-question session completes, without granting a separate score, currency, or duplicate growth reward.

#### Scenario: Invited session completes
- **WHEN** the learner finishes all three attempts launched from a pet invitation
- **THEN** control returns to the launching surface and the pet performs a short activity-appropriate reaction

#### Scenario: Furniture session completes
- **WHEN** the learner finishes all three attempts launched from furniture
- **THEN** pet home shows the same lightweight completion reaction in addition to any already-earned mastery celebration

#### Scenario: Session exits early
- **WHEN** the learner leaves before completing all three attempts
- **THEN** no completion reaction is shown and existing per-attempt persistence remains unchanged
