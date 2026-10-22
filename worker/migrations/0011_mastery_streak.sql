ALTER TABLE practice_progress
ADD COLUMN correct_streak_started_at TEXT;

CREATE INDEX practice_records_progress_streak_idx
ON practice_records(
  student_id, textbook_key, question_id, direction, is_correct, occurred_at
);

UPDATE practice_progress
SET correct_streak_started_at = (
  SELECT MIN(record.occurred_at)
  FROM practice_records AS record
  WHERE record.student_id = practice_progress.student_id
    AND record.textbook_key = practice_progress.textbook_key
    AND record.question_id || ':' || record.direction = practice_progress.question_key
    AND record.is_correct = 1
    AND (
      practice_progress.last_wrong_at IS NULL
      OR record.occurred_at > practice_progress.last_wrong_at
    )
);

DROP TRIGGER practice_records_progress_after_insert;

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

  UPDATE practice_progress
  SET correct_streak_started_at = (
    SELECT MIN(record.occurred_at)
    FROM practice_records AS record
    WHERE record.student_id = practice_progress.student_id
      AND record.textbook_key = practice_progress.textbook_key
      AND record.question_id || ':' || record.direction = practice_progress.question_key
      AND record.is_correct = 1
      AND (
        practice_progress.last_wrong_at IS NULL
        OR record.occurred_at > practice_progress.last_wrong_at
      )
  )
  WHERE student_id = NEW.student_id
    AND textbook_key = NEW.textbook_key
    AND question_key = NEW.question_id || ':' || NEW.direction;
END;
