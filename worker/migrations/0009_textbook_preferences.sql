CREATE TABLE textbook_preferences (
  account_id TEXT PRIMARY KEY NOT NULL REFERENCES accounts(id),
  grade INTEGER NOT NULL CHECK (grade BETWEEN 1 AND 6),
  semester TEXT NOT NULL CHECK (semester IN ('a', 'b')),
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
