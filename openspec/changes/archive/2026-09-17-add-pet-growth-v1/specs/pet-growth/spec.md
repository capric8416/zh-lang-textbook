## ADDED Requirements

### Requirement: One global default dog profile persists locally
The system SHALL maintain one versioned local pet profile shared across textbooks, initialized as species `dog` and breed `default`, with total growth points, completed major stages, and claimed event keys.

#### Scenario: First launch initializes a dog
- **WHEN** no pet profile has been stored
- **THEN** the system creates a default dog with zero growth points and zero completed major stages

#### Scenario: App restarts preserve growth
- **WHEN** the app restarts after growth has been awarded
- **THEN** the same species, breed, growth points, stages, and claimed events are restored

### Requirement: Growth rewards cannot be farmed
The system MUST award growth points once per stable mastery event and MUST grant one major growth stage once per completed unit.

#### Scenario: Unique question is first mastered
- **WHEN** an unclaimed question-mastery event is synchronized
- **THEN** the dog receives 10 growth points exactly once

#### Scenario: Lesson thresholds award configured growth
- **WHEN** the 60%, 80%, 90%, or 100% lesson milestone is first claimed
- **THEN** the dog receives respectively 30, 20, 20, or 30 growth points exactly once

#### Scenario: Unit completion advances a major stage
- **WHEN** an unclaimed unit-completion event is synchronized
- **THEN** the dog receives 100 growth points and advances exactly one major growth stage

### Requirement: Existing learning history is backfilled silently
The system SHALL derive growth from existing practice history when a textbook is first synchronized and SHALL support a silent synchronization mode that emits no celebration UI.

#### Scenario: Existing learner opens the mode page
- **WHEN** historical practice already satisfies question, lesson, or unit events and the mode page performs silent synchronization
- **THEN** all corresponding rewards are claimed and persisted without displaying old animations

### Requirement: Mode page presents pet growth
The system SHALL show a compact dog card on the learning mode page containing the dog, total growth points, completed major-stage count, and selected-textbook progress toward the next incomplete lesson.

#### Scenario: Learner has an incomplete lesson
- **WHEN** the mode page loads a textbook with an eligible incomplete lesson
- **THEN** the pet card shows that lesson's mastered and total question counts and its mastery percentage

#### Scenario: Selected textbook is fully complete
- **WHEN** all eligible units in the selected textbook are complete
- **THEN** the pet card shows a completed-textbook state while retaining global dog growth

### Requirement: Lesson milestones trigger a lower-right dog reaction
The system SHALL display a one-time lower-right dog run/reaction for a newly reached lesson milestone, with expression and aura color varying by threshold.

#### Scenario: Lesson reaches 60 percent
- **WHEN** grading causes a lesson to first reach 60% mastery
- **THEN** the dog performs the standard happy running reaction in the lower-right area

#### Scenario: Higher milestone is reached
- **WHEN** grading first reaches 80%, 90%, or 100%
- **THEN** the dog uses the configured increasingly rare expression and color treatment for that threshold

#### Scenario: Several lesson milestones are crossed together
- **WHEN** one grading result crosses multiple lesson thresholds
- **THEN** the system displays one dog reaction using the highest crossed threshold

### Requirement: Unit completion triggers full-screen celebration
The system SHALL display a one-time full-screen confetti celebration with the dog when grading first completes a unit.

#### Scenario: Final eligible lesson passes
- **WHEN** grading raises the final below-60% lesson in a unit to at least 60%
- **THEN** the lesson reaction completes and is followed by a full-screen unit celebration

#### Scenario: Completed unit is revisited
- **WHEN** the learner revisits or practices a unit whose completion event was already claimed
- **THEN** the full-screen celebration does not replay

### Requirement: Pet visuals are accessible and extensible
The system SHALL render the v1 dog through a reusable appearance and expression interface, SHALL play no automatic sound, and SHALL reduce motion when the platform requests disabled animations.

#### Scenario: Reduced motion is enabled
- **WHEN** the device reports disabled animations
- **THEN** the system replaces running and confetti motion with a brief static milestone presentation

#### Scenario: Future breed is added
- **WHEN** a later version registers another cat or dog appearance descriptor
- **THEN** existing growth persistence and milestone logic can use it without a schema change
