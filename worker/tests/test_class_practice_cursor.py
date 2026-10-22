"""Exercise stable class-history cursor pagination against the D1 SQL."""
import re
import sqlite3
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class ClassPracticeCursorTests(unittest.TestCase):
    def setUp(self):
        self.db = sqlite3.connect(':memory:')
        self.addCleanup(self.db.close)
        for name in (
            '0001_accounts.sql',
            '0004_practice_records.sql',
            '0005_nullable_practice_record_class.sql',
            '0010_class_practice_records_cursor.sql',
        ):
            self.db.executescript((ROOT / 'migrations' / name).read_text())
        self.db.row_factory = sqlite3.Row
        self.db.execute(
            "INSERT INTO accounts(id,username,display_name,password_hash,password_salt,password_iterations,role) "
            "VALUES('student','student','学生','hash','salt',1,'student')"
        )
        self.db.execute(
            "INSERT INTO accounts(id,username,display_name,password_hash,password_salt,password_iterations,role) "
            "VALUES('admin','admin','教师','hash','salt',1,'class_admin')"
        )
        self.db.execute(
            "INSERT INTO classes(id,name,created_by,school_admin_id) "
            "VALUES('class-a','测试班','admin','admin')"
        )
        source = (ROOT / 'src/db/practice_records.rs').read_text()
        section = source.split('pub(crate) async fn list_for_class_cursor_page(')[1]
        self.next_sql, self.first_sql = re.findall(r'db.prepare\("([^"]+)"\)', section)[:2]
        for record_id in ('a', 'b', 'c'):
            self.insert(record_id, '2026-10-22T10:00:00.000Z')

    def insert(self, record_id, occurred_at):
        self.db.execute(
            '''INSERT INTO practice_records
               (id,student_id,class_id,textbook_key,question_id,chapter_id,
                question_kind,category,source,direction,prompt,student_answer,
                expected_answer,is_correct,occurred_at)
               VALUES(?, 'student', 'class-a', 'book', 'q', 'chapter', 'word',
                      'word', 'lesson', 'writeHanzi', 'q', 'a', 'a', 1, ?)''',
            (record_id, occurred_at),
        )

    def test_snapshot_cursor_excludes_new_rows_and_has_no_gaps(self):
        snapshot = self.db.execute(
            'SELECT MAX(rowid) FROM practice_records WHERE class_id=?', ('class-a',)
        ).fetchone()[0]
        first = self.db.execute(self.first_sql, ('class-a', snapshot, 2)).fetchall()
        self.assertEqual([row['id'] for row in first], ['a', 'b'])

        # Both a newer and a backdated record arrive after the export starts.
        self.insert('newest', '2026-10-23T10:00:00.000Z')
        self.insert('backfilled', '2026-10-21T10:00:00.000Z')
        cursor = first[-1]
        rest = self.db.execute(
            self.next_sql,
            (
                'class-a', snapshot, cursor['occurred_at'],
                cursor['occurred_at'], cursor['id'], 500,
            ),
        ).fetchall()
        self.assertEqual([row['id'] for row in first + rest], ['a', 'b', 'c'])

    def test_class_time_id_index_supports_first_page_sort(self):
        snapshot = self.db.execute(
            'SELECT MAX(rowid) FROM practice_records WHERE class_id=?', ('class-a',)
        ).fetchone()[0]
        plan = self.db.execute(
            'EXPLAIN QUERY PLAN ' + self.first_sql, ('class-a', snapshot, 500)
        ).fetchall()
        self.assertIn(
            'practice_records_class_time_id_idx', str([tuple(row) for row in plan])
        )


if __name__ == '__main__':
    unittest.main()
