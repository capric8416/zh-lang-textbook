# pet-learning-goals Specification

## Purpose
TBD - created by archiving change enhance-pet-learning-motivation-v7. Update Purpose after archive.
## Requirements
### Requirement: Current textbook exposes an actionable learning goal
The system SHALL derive a bounded goal for the selected textbook and current unit from existing learning records, including current progress, target, remaining amount, action label, and a visible companion outcome.

#### Scenario: Unit has unfinished learning
- **WHEN** the learner opens a companion surface with an incomplete current unit
- **THEN** the goal shows the current unit, a deterministic progress value, the remaining actionable amount, and a three-question or standard-practice action

#### Scenario: Unit goal is completed
- **WHEN** the goal reaches its target through existing mastery or lesson progress
- **THEN** the goal shows a completed state and points to the next available unit or target without resetting the prior result

#### Scenario: Fewer than three compatible attempts exist
- **WHEN** the current goal cannot launch a three-question activity
- **THEN** the goal offers standard practice or explains that more textbook content is needed without importing another textbook

### Requirement: Goals do not create a second reward ledger
The system SHALL calculate goal progress from existing practice and growth records, shall not award separate points or currency, and shall keep goal completion idempotent.

#### Scenario: Existing records change
- **WHEN** the learner answers a normal or quick-practice attempt
- **THEN** the next goal projection reflects the same persisted learning record without a parallel counter

#### Scenario: Goal surface rebuilds
- **WHEN** the goal card is rebuilt or reopened
- **THEN** its completed state and outcome remain stable and no duplicate reward or celebration is created

### Requirement: Goal feedback previews a concrete room result
The system SHALL associate each goal kind with a short pet action and a furniture or room outcome that can be shown before and after the goal is completed.

#### Scenario: Goal is presented
- **WHEN** the learner views an incomplete goal
- **THEN** the pet names the next action in neutral language and previews the associated room change

#### Scenario: Goal is completed
- **WHEN** the learner completes the goal threshold
- **THEN** the pet and room show one bounded completion feedback and the next goal becomes available

