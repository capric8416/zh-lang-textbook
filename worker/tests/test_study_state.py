import sqlite3
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class StudyStateTests(unittest.TestCase):
    def setUp(self):
        self.db = sqlite3.connect(':memory:')
        self.addCleanup(self.db.close)
        for name in ('0004_practice_records.sql',
                     '0005_nullable_practice_record_class.sql'):
            self.db.executescript((ROOT / 'migrations' / name).read_text())
        self.insert('first', 1, '2026-10-20T00:00:00Z')
        self.db.executescript(
            (ROOT / 'migrations' / '0008_study_state.sql').read_text())
        self.db.executescript(
            (ROOT / 'migrations' / '0011_mastery_streak.sql').read_text())

    def insert(self, record_id, correct, occurred_at):
        self.db.execute('''INSERT INTO practice_records
            (id,student_id,class_id,textbook_key,question_id,chapter_id,
             question_kind,category,source,direction,prompt,student_answer,
             expected_answer,is_correct,occurred_at)
            VALUES(?, 'student-a', NULL, 'book', 'q1', 'chapter', 'word',
                   'word', 'lesson', 'writeHanzi', 'q', 'a', 'a', ?, ?)''',
            (record_id, correct, occurred_at))

    def test_migration_seeds_existing_records_and_trigger_tracks_new_ones(self):
        seeded_streak = self.db.execute(
            'SELECT correct_streak_started_at FROM practice_progress'
        ).fetchone()
        self.assertEqual(seeded_streak[0], '2026-10-20T00:00:00Z')

        self.insert('second', 0, '2026-10-21T00:00:00Z')
        row = self.db.execute('SELECT * FROM practice_progress').fetchone()
        self.assertEqual(row[3:5], (1, 1))
        self.assertEqual(row[5], '2026-10-20T00:00:00Z')
        self.assertEqual(row[6], '2026-10-21T00:00:00Z')
        self.assertIsNone(row[7])

    def test_mastery_streak_uses_correct_attempts_after_latest_wrong(self):
        self.insert('second', 0, '2026-10-21T00:00:00Z')
        self.insert('third', 1, '2026-10-22T00:00:00Z')
        row = self.db.execute(
            'SELECT correct_streak_started_at FROM practice_progress'
        ).fetchone()
        self.assertEqual(row[0], '2026-10-22T00:00:00Z')

        self.insert('fourth', 1, '2026-10-23T00:00:00Z')
        row = self.db.execute(
            'SELECT correct_streak_started_at FROM practice_progress'
        ).fetchone()
        self.assertEqual(row[0], '2026-10-22T00:00:00Z')

        self.insert('fifth', 0, '2026-10-24T00:00:00Z')
        row = self.db.execute(
            'SELECT correct_streak_started_at FROM practice_progress'
        ).fetchone()
        self.assertIsNone(row[0])

    def test_duplicate_record_id_does_not_increment_progress(self):
        self.db.execute('''INSERT INTO practice_records
            (id,student_id,class_id,textbook_key,question_id,chapter_id,
             question_kind,category,source,direction,prompt,student_answer,
             expected_answer,is_correct,occurred_at)
            VALUES('first','student-a',NULL,'book','q1','chapter','word','word',
                   'lesson','writeHanzi','q','a','a',1,'2026-10-22T00:00:00Z')
            ON CONFLICT(id) DO NOTHING''')
        row = self.db.execute(
            'SELECT correct_count,wrong_count FROM practice_progress'
        ).fetchone()
        self.assertEqual(row, (1, 0))


if __name__ == '__main__':
    unittest.main()
