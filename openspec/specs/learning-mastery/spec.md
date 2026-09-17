## Purpose

Define how practice history becomes stable lesson and unit mastery events.

## Requirements

### Requirement: Lesson mastery is based on unique questions
The system SHALL calculate lesson mastery from eligible unique catalog questions and count a question as mastered when any supported practice direction has at least one correct attempt.

#### Scenario: Repeated answers do not inflate mastery
- **WHEN** a mastered question is answered again
- **THEN** it contributes exactly once and later wrong answers do not revoke mastery

### Requirement: Lessons expose four monotonic milestones
The system SHALL expose one-time milestones at 60%, 80%, 90%, and 100% mastery, with 60% passing a lesson.

#### Scenario: Empty lesson
- **WHEN** a chapter has no eligible questions
- **THEN** it is excluded from mastery and cannot pass

### Requirement: Units complete only when every eligible lesson passes
The system SHALL complete a non-appendix unit only when every chapter containing eligible questions reaches 60% mastery.

#### Scenario: Empty chapters do not block
- **WHEN** all eligible chapters pass and other chapters are empty
- **THEN** the unit completes

### Requirement: Mastery events are stable and idempotent
The system MUST use textbook-scoped event keys for question, lesson-threshold, and unit events.

#### Scenario: Synchronization repeats
- **WHEN** unchanged progress is synchronized again
- **THEN** no event is rewarded twice
