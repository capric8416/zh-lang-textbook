CREATE TABLE practice_records_new (
  id TEXT PRIMARY KEY NOT NULL,
  student_id TEXT NOT NULL REFERENCES accounts(id),
  class_id TEXT REFERENCES classes(id),
  textbook_key TEXT NOT NULL,
  question_id TEXT NOT NULL,
  chapter_id TEXT NOT NULL,
  question_kind TEXT NOT NULL,
  category TEXT NOT NULL,
  source TEXT NOT NULL,
  direction TEXT NOT NULL,
  prompt TEXT NOT NULL,
  student_answer TEXT NOT NULL,
  expected_answer TEXT NOT NULL,
  is_correct INTEGER NOT NULL CHECK(is_correct IN (0,1)),
  occurred_at TEXT NOT NULL,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO practice_records_new (
  id, student_id, class_id, textbook_key, question_id, chapter_id,
  question_kind, category, source, direction, prompt, student_answer,
  expected_answer, is_correct, occurred_at, created_at
)
SELECT
  id, student_id, class_id, textbook_key, question_id, chapter_id,
  question_kind, category, source, direction, prompt, student_answer,
  expected_answer, is_correct, occurred_at, created_at
FROM practice_records;

DROP TABLE practice_records;
ALTER TABLE practice_records_new RENAME TO practice_records;

CREATE INDEX practice_records_class_student_time_idx
  ON practice_records(class_id, student_id, occurred_at DESC);
