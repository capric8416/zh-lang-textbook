## Purpose

Define fixed three-question practice sessions launched from pet-home furniture using only the current textbook and existing learning records.
## Requirements
### Requirement: Quick practice uses exactly three current-textbook attempts
The system SHALL create a quick-practice session containing exactly three compatible question-direction attempts from the textbook through which pet home was opened.

#### Scenario: Enough candidates exist
- **WHEN** a learner starts quick practice and the current textbook has at least three compatible attempts
- **THEN** the session contains exactly three attempts and no attempt from another textbook

#### Scenario: Too few candidates exist
- **WHEN** the current textbook has fewer than three compatible attempts after fallback
- **THEN** the furniture entry is unavailable and explains that more practice content is needed

### Requirement: Selection prioritizes useful review
The system MUST rank candidates by current mistakes, then unmastered attempts, then least-practiced attempts, and finally mastered attempts, using stable tie-breaking.

#### Scenario: Three current mistakes exist
- **WHEN** the learner opens mistake-first quick practice with at least three current mistakes
- **THEN** all three selected attempts are current mistakes

#### Scenario: Preferred candidates are insufficient
- **WHEN** a furniture-specific preferred subset contains fewer than three attempts
- **THEN** compatible candidates from the same textbook fill the remaining positions according to the standard ranking

### Requirement: Furniture selects a focused activity
The system SHALL use the activated furniture to choose a preferred activity while keeping the session within the current textbook.

#### Scenario: Character practice starts
- **WHEN** character-oriented furniture starts quick practice
- **THEN** hanzi and pinyin attempts are preferred

#### Scenario: Read-aloud practice starts
- **WHEN** the flower pot starts quick practice
- **THEN** read-aloud attempts for words or sentences are preferred and single-character content is excluded

### Requirement: Quick practice reuses normal learning records
The system SHALL grade and persist every answered attempt through the existing progress, mistake, mastery, and pet-growth systems without a separate score or reward ledger.

#### Scenario: Learner answers a quick-practice item
- **WHEN** an answer is graded
- **THEN** its result immediately updates the same record used by normal practice

#### Scenario: Learner exits early
- **WHEN** the learner leaves before answering all three items
- **THEN** completed results remain saved and unanswered items create no result

### Requirement: Three-question completion returns pet feedback
The system SHALL end the session after the third graded attempt and display or trigger the existing pet completion feedback and any newly earned mastery celebration.

#### Scenario: Third attempt completes
- **WHEN** the learner finishes the third attempt
- **THEN** quick practice ends, progress is synchronized, and control returns to pet home with completion feedback

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

