PRAGMA foreign_keys = ON;
CREATE TABLE accounts (
  id TEXT PRIMARY KEY NOT NULL,
  username TEXT NOT NULL UNIQUE COLLATE NOCASE,
  display_name TEXT NOT NULL,
  role TEXT NOT NULL CHECK(role IN ('super_admin','group_admin','school_admin','class_admin','student')),
  parent_id TEXT REFERENCES accounts(id),
  password_hash TEXT NOT NULL,
  password_salt TEXT NOT NULL,
  password_iterations INTEGER NOT NULL DEFAULT 600000,
  must_change_password INTEGER NOT NULL DEFAULT 0,
  disabled INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX accounts_parent_idx ON accounts(parent_id,role);
CREATE UNIQUE INDEX root_super_admin_unique ON accounts(role) WHERE role='super_admin' AND parent_id IS NULL;
CREATE TABLE sessions (token_hash TEXT PRIMARY KEY NOT NULL, account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE, expires_at INTEGER NOT NULL, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP);
CREATE INDEX sessions_account_idx ON sessions(account_id,expires_at);
CREATE TABLE classes (id TEXT PRIMARY KEY NOT NULL, name TEXT NOT NULL, created_by TEXT NOT NULL REFERENCES accounts(id), school_admin_id TEXT NOT NULL REFERENCES accounts(id), disabled INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP);
CREATE INDEX classes_owner_idx ON classes(created_by);
CREATE TABLE class_memberships (student_id TEXT PRIMARY KEY NOT NULL REFERENCES accounts(id) ON DELETE CASCADE, class_id TEXT NOT NULL REFERENCES classes(id), joined_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP);
CREATE INDEX memberships_class_idx ON class_memberships(class_id);
CREATE TABLE class_join_codes (code_hash TEXT PRIMARY KEY NOT NULL, class_id TEXT NOT NULL REFERENCES classes(id) ON DELETE CASCADE, created_by TEXT NOT NULL REFERENCES accounts(id), expires_at INTEGER NOT NULL, revoked INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP);
