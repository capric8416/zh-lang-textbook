CREATE TABLE practice_progress (
  student_id TEXT NOT NULL REFERENCES accounts(id),
  textbook_key TEXT NOT NULL,
  question_key TEXT NOT NULL,
  correct_count INTEGER NOT NULL DEFAULT 0,
  wrong_count INTEGER NOT NULL DEFAULT 0,
  last_correct_at TEXT,
  last_wrong_at TEXT,
  PRIMARY KEY(student_id, textbook_key, question_key)
);

INSERT INTO practice_progress(
  student_id, textbook_key, question_key, correct_count, wrong_count,
  last_correct_at, last_wrong_at
)
SELECT
  student_id,
  textbook_key,
  question_id || ':' || direction,
  SUM(CASE WHEN is_correct = 1 THEN 1 ELSE 0 END),
  SUM(CASE WHEN is_correct = 0 THEN 1 ELSE 0 END),
  MAX(CASE WHEN is_correct = 1 THEN occurred_at END),
  MAX(CASE WHEN is_correct = 0 THEN occurred_at END)
FROM practice_records
GROUP BY student_id, textbook_key, question_id, direction;

CREATE TRIGGER practice_records_progress_after_insert
AFTER INSERT ON practice_records
BEGIN
  INSERT INTO practice_progress(
    student_id, textbook_key, question_key, correct_count, wrong_count,
    last_correct_at, last_wrong_at
  ) VALUES(
    NEW.student_id,
    NEW.textbook_key,
    NEW.question_id || ':' || NEW.direction,
    CASE WHEN NEW.is_correct = 1 THEN 1 ELSE 0 END,
    CASE WHEN NEW.is_correct = 0 THEN 1 ELSE 0 END,
    CASE WHEN NEW.is_correct = 1 THEN NEW.occurred_at END,
    CASE WHEN NEW.is_correct = 0 THEN NEW.occurred_at END
  )
  ON CONFLICT(student_id, textbook_key, question_key) DO UPDATE SET
    correct_count = correct_count + CASE WHEN NEW.is_correct = 1 THEN 1 ELSE 0 END,
    wrong_count = wrong_count + CASE WHEN NEW.is_correct = 0 THEN 1 ELSE 0 END,
    last_correct_at = CASE
      WHEN NEW.is_correct = 1 AND (last_correct_at IS NULL OR NEW.occurred_at > last_correct_at)
      THEN NEW.occurred_at ELSE last_correct_at END,
    last_wrong_at = CASE
      WHEN NEW.is_correct = 0 AND (last_wrong_at IS NULL OR NEW.occurred_at > last_wrong_at)
      THEN NEW.occurred_at ELSE last_wrong_at END;
END;

CREATE TABLE pet_profiles (
  account_id TEXT PRIMARY KEY NOT NULL REFERENCES accounts(id),
  profile_json TEXT NOT NULL,
  revision INTEGER NOT NULL DEFAULT 1,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
