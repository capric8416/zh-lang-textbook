## 1. Mastery and Pet Data

- [x] 1.1 Add lesson/unit mastery models and deterministic calculations over `PracticeCatalog`, `Textbook`, and `PracticeProgress`.
- [x] 1.2 Add unit tests for unique-question mastery, 60/80/90/100 thresholds, empty chapters, monotonic progress, and unit completion.
- [x] 1.3 Add a versioned global pet profile/store with species, breed, growth points, major stages, and claimed event keys.

## 2. Reward Synchronization

- [x] 2.1 Implement idempotent pet-growth synchronization with textbook-scoped question, lesson-threshold, and unit event keys.
- [x] 2.2 Implement silent historical backfill and emitted-event prioritization for newly crossed lesson and unit milestones.
- [x] 2.3 Add tests for reward values, repeat synchronization, cross-textbook key isolation, persistence, and silent backfill.

## 3. Pet Presentation

- [x] 3.1 Implement an extensible custom-painted default dog with threshold-specific expressions and aura colors.
- [x] 3.2 Implement the compact mode-page pet card with growth points, major-stage count, and next-lesson progress.
- [x] 3.3 Implement serialized lower-right lesson reactions and full-screen unit confetti, including reduced-motion behavior.

## 4. Application Integration

- [x] 4.1 Silently synchronize historical pet growth when the mode page loads and refresh the card after returning from practice.
- [x] 4.2 Synchronize pet growth after OCR and read-aloud grading, and play only newly emitted celebrations in order.
- [x] 4.3 Add widget tests for the pet card, lesson reaction selection, unit celebration, and no duplicate replay.

## 5. Verification

- [x] 5.1 Format the affected Dart sources and run `flutter analyze`.
- [x] 5.2 Run the full Flutter test suite and verify the final diff contains no whitespace errors.
