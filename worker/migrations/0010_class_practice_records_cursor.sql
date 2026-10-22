CREATE INDEX IF NOT EXISTS practice_records_class_time_id_idx
ON practice_records(class_id, occurred_at DESC, id ASC);
