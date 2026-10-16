CREATE TABLE class_membership_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  student_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
  class_id TEXT NOT NULL REFERENCES classes(id),
  joined_at TEXT NOT NULL,
  left_at TEXT,
  CHECK (left_at IS NULL OR julianday(left_at) >= julianday(joined_at))
);

CREATE INDEX class_membership_history_student_time_idx
  ON class_membership_history(student_id, joined_at DESC, left_at);

INSERT INTO class_membership_history(student_id, class_id, joined_at, left_at)
SELECT student_id, class_id, joined_at, NULL
FROM class_memberships;

CREATE TRIGGER class_membership_history_after_insert
AFTER INSERT ON class_memberships
BEGIN
  INSERT INTO class_membership_history(student_id, class_id, joined_at, left_at)
  VALUES(NEW.student_id, NEW.class_id, NEW.joined_at, NULL);
END;

CREATE TRIGGER class_membership_history_after_class_change
AFTER UPDATE OF class_id ON class_memberships
WHEN OLD.class_id <> NEW.class_id
BEGIN
  UPDATE class_membership_history
  SET left_at = NEW.joined_at
  WHERE student_id = OLD.student_id
    AND class_id = OLD.class_id
    AND left_at IS NULL;

  INSERT INTO class_membership_history(student_id, class_id, joined_at, left_at)
  VALUES(NEW.student_id, NEW.class_id, NEW.joined_at, NULL);
END;

CREATE TRIGGER class_membership_history_after_leave
AFTER DELETE ON class_memberships
BEGIN
  UPDATE class_membership_history
  SET left_at = strftime('%Y-%m-%dT%H:%M:%fZ', 'now')
  WHERE student_id = OLD.student_id
    AND class_id = OLD.class_id
    AND left_at IS NULL;
END;
