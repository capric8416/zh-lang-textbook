## MODIFIED Requirements

### Requirement: Growth rewards cannot be farmed
The system MUST award question and lesson rewards once, grant one major stage per completed unit, derive breed, decoration, and furniture unlocks idempotently from the resulting stage, and expose newly unlocked furniture for one-time visible room feedback without awarding an additional reward.

#### Scenario: Synchronization repeats
- **WHEN** the same practice history is synchronized again
- **THEN** rewards are not duplicated, furniture unlocks remain stable, and acknowledged furniture reveals are not recreated

#### Scenario: A new furniture stage is reached
- **WHEN** synchronization first unlocks furniture for a newly completed major stage
- **THEN** the furniture is marked for one visible reveal while growth points and major-stage awards remain governed by existing claimed events
