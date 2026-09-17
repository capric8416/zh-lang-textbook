## ADDED Requirements

### Requirement: Lesson mastery is based on unique questions
The system SHALL calculate a lesson's mastery percentage from eligible unique catalog questions, and SHALL treat a question as mastered when any currently supported practice direction has at least one correct attempt.

#### Scenario: First correct answer masters a question
- **WHEN** a learner records the first correct attempt for any supported direction of an unmastered question
- **THEN** the question contributes exactly once to the lesson's mastered-question count

#### Scenario: Repeated correct answers do not inflate mastery
- **WHEN** a learner answers an already-mastered question correctly again in the same or another direction
- **THEN** the lesson's mastered-question count remains unchanged

#### Scenario: Later wrong answers do not revoke mastery
- **WHEN** a mastered question later receives an incorrect attempt
- **THEN** the question remains mastered for lesson-stage calculation while continuing to follow mistake-practice rules

### Requirement: Lessons expose four monotonic milestones
The system SHALL expose one-time lesson milestones at 60%, 80%, 90%, and 100% mastery, and SHALL consider the lesson passed at 60%.

#### Scenario: Lesson reaches its passing milestone
- **WHEN** the integer ratio of mastered to eligible questions first reaches at least 60%
- **THEN** the system marks the lesson passed and emits the 60% milestone exactly once

#### Scenario: One answer crosses multiple thresholds
- **WHEN** a newly mastered question causes a lesson to cross more than one unclaimed threshold
- **THEN** the system claims every crossed threshold and identifies the highest crossed threshold for visual reaction

#### Scenario: Empty lesson is not completed
- **WHEN** a chapter contains no eligible practice questions
- **THEN** the system excludes it from mastery percentages and does not mark it passed

### Requirement: Units complete only when every eligible lesson passes
The system SHALL complete a non-appendix textbook unit only when every chapter in that unit containing eligible questions has reached the 60% lesson milestone.

#### Scenario: All eligible lessons pass
- **WHEN** every eligible lesson in a unit reaches at least 60% mastery for the first time
- **THEN** the system emits one unit-completion event

#### Scenario: One eligible lesson remains below threshold
- **WHEN** at least one eligible lesson in the unit remains below 60%
- **THEN** the unit remains incomplete regardless of the unit-wide average

#### Scenario: Empty chapters do not block a unit
- **WHEN** a unit contains chapters without eligible questions and every eligible chapter has passed
- **THEN** the system completes the unit

### Requirement: Mastery events are stable and idempotent
The system MUST assign stable textbook-scoped keys to question, lesson-threshold, and unit events so synchronization can distinguish newly earned events from previously claimed events.

#### Scenario: Synchronization repeats without new learning
- **WHEN** mastery synchronization runs multiple times with unchanged practice progress
- **THEN** no previously claimed mastery event is returned or rewarded again

#### Scenario: Different textbooks reuse a chapter identifier
- **WHEN** two textbooks contain the same local chapter or question identifier
- **THEN** their event keys remain distinct through the textbook key
