## 1. Session selection

- [x] 1.1 Add immutable furniture-action and three-attempt quick-session descriptors.
- [x] 1.2 Implement deterministic current-textbook candidate ranking and three-attempt selection.
- [x] 1.3 Add furniture-specific preferences, compatible fallback, and unavailable-state reporting.

## 2. Practice integration

- [x] 2.1 Pass textbook selection and parsed textbook from mode page into pet home.
- [x] 2.2 Add optional fixed-session support to the existing practice page without changing normal practice behavior.
- [x] 2.3 Display quick-session progress, stop after three graded attempts, and preserve immediate result recording on early exit.
- [x] 2.4 Synchronize existing mastery and pet feedback after quick-practice completion.

## 3. Furniture actions

- [x] 3.1 Make configured room furniture keyboard/touch accessible and expose action descriptions.
- [x] 3.2 Connect study desk to normal practice and review furniture to current-textbook three-question sessions.
- [x] 3.3 Show an explanatory unavailable state when fewer than three compatible attempts exist.

## 4. Verification

- [x] 4.1 Add selector tests for priority ordering, furniture preferences, fallback, and textbook isolation.
- [x] 4.2 Add widget tests for furniture activation, 1/3-to-3/3 flow, early exit, and completion return.
- [x] 4.3 Run formatter, analyzer, and the full Flutter test suite.
