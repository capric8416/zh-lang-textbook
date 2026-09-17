## Context

Pet home receives no textbook context today, while `ModePage` already owns the selected `TextbookSelection` and parsed `Textbook`. `PracticePage`, `PracticeCatalog`, and `PracticeProgressStore` already implement question rendering, grading, mistake accounting, speech/OCR flows, and pet-growth synchronization. v4 should compose these pieces rather than create a second practice engine.

## Goals / Non-Goals

**Goals:**

- Pass current-textbook context into pet home and furniture actions.
- Select exactly three compatible questions using a testable priority algorithm.
- Reuse the existing practice/grading/progress pipeline.
- Make completed attempts durable immediately and allow early exit.
- Give completion feedback through the existing pet system.

**Non-Goals:**

- No cross-textbook selection, endless mode, configurable question count, new scoring, currency, streaks, or separate progress store.
- No replacement of the existing full practice and mistake-practice entries.

## Decisions

1. **Introduce a pure quick-practice selector.** It accepts the current catalog, progress, and furniture action, returns three question/direction attempts, and uses stable tie-breaking. This keeps tests deterministic and avoids storing generated sessions.
2. **Use prioritized filling rather than strict buckets.** Selection orders current mistakes first, then unmastered attempts, then least-practiced attempts, then mastered attempts. Furniture applies a preferred subset; if that subset has fewer than three candidates, compatible current-textbook candidates fill the session. If the entire catalog has fewer than three compatible attempts, the entry is shown unavailable instead of creating a shorter session.
3. **Reuse `PracticePage` with an optional session descriptor.** Quick mode supplies its fixed attempt list, shows `1/3` progress, stops after the third result, and returns a completion result. Existing grading, answer recording, mistake rules, and speech/OCR services remain authoritative.
4. **Persist each answer immediately.** Early exit needs no special save operation; attempts already recorded remain, while unanswered items create no records.
5. **Keep furniture semantics small.** The study desk resumes standard practice. Bookcase prefers mixed review, toy box prefers mistakes, character-oriented furniture prefers hanzi/pinyin directions, and flower pot prefers word/sentence read-aloud. All queries remain within the current textbook.
6. **Synchronize pet growth after quick practice.** The mode/pet-home flow reloads progress after return and invokes existing growth synchronization, allowing normal lesson or unit celebrations without a new reward type.

## Risks / Trade-offs

- [Some textbooks may not have three candidates for a narrow action] → fill from compatible current-textbook attempts, then disable the entry only if the total remains below three.
- [PracticePage gains more configuration] → isolate the request in a small immutable session descriptor and keep normal defaults unchanged.
- [Repeated generation could choose the same three attempts] → least-practiced ordering naturally rotates candidates as attempts are recorded.
- [Furniture labels may imply stronger filtering than is possible] → explain the preferred activity in the entry subtitle and use general fallback only to reach three.

## Migration Plan

No persisted schema migration is required. Existing profiles, rooms, furniture, progress, and rewards remain valid. The feature can be removed by dropping furniture callbacks and the optional quick-session path without converting stored data.

## Open Questions

Future versions may add a learning-history album, but v4 intentionally stops after focused three-question sessions.
