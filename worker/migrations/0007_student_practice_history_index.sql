CREATE INDEX IF NOT EXISTS practice_records_student_time_id_idx
ON practice_records(student_id, occurred_at DESC, id ASC);
