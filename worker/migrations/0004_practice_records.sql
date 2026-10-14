CREATE TABLE practice_records (
  id TEXT PRIMARY KEY NOT NULL,
  student_id TEXT NOT NULL REFERENCES accounts(id),
  class_id TEXT NOT NULL REFERENCES classes(id),
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
CREATE INDEX practice_records_class_student_time_idx
  ON practice_records(class_id, student_id, occurred_at DESC);
