"""Exercise the actual D1 SQL using SQLite, including tenant and cursor boundaries."""
import re
import sqlite3
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class StudentHistoryTests(unittest.TestCase):
    def setUp(self):
        self.db = sqlite3.connect(':memory:')
        self.addCleanup(self.db.close)
        for name in ('0004_practice_records.sql', '0005_nullable_practice_record_class.sql',
                     '0007_student_practice_history_index.sql'):
            self.db.executescript((ROOT / 'migrations' / name).read_text())
        source = (ROOT / 'src/db/practice_records.rs').read_text()
        section = source.split('pub(crate) async fn list_for_student_page(')[1]
        self.next_sql, self.first_sql = re.findall(r'db.prepare\("([^"]+)"\)', section)[:2]
        self.db.row_factory = sqlite3.Row
        for id_, student, class_ in [('a', 'student', None), ('b', 'student', 'old'),
                                     ('c', 'student', 'current'), ('d', 'other', 'current')]:
            self.insert(id_, student, class_)

    def insert(self, id_, student, class_, time='2026-10-21T10:00:00Z'):
        self.db.execute('''INSERT INTO practice_records
            (id,student_id,class_id,textbook_key,question_id,chapter_id,question_kind,
             category,source,direction,prompt,student_answer,expected_answer,is_correct,occurred_at)
            VALUES(?,?,?,'book','q','chapter','word','word','lesson','writeHanzi','q','a','a',1,?)''',
            (id_, student, class_, time))

    def test_student_scope_includes_old_and_null_classes(self):
        rows = self.db.execute(self.first_sql, ('student', 500)).fetchall()
        self.assertEqual([row['id'] for row in rows], ['a', 'b', 'c'])
        self.assertEqual({row['class_id'] for row in rows}, {None, 'old', 'current'})

    def test_cursor_ties_and_concurrent_new_records(self):
        first = self.db.execute(self.first_sql, ('student', 2)).fetchall()
        self.insert('new', 'student', None, '2026-10-22T10:00:00Z')
        last = first[-1]
        rest = self.db.execute(self.next_sql, ('student', last['occurred_at'],
                              last['occurred_at'], last['id'], 500)).fetchall()
        self.assertEqual([row['id'] for row in first + rest], ['a', 'b', 'c'])

    def test_index_supports_student_sort(self):
        plan = self.db.execute('EXPLAIN QUERY PLAN ' + self.first_sql, ('student', 500)).fetchall()
        self.assertIn('practice_records_student_time_id_idx', str([tuple(row) for row in plan]))


if __name__ == '__main__':
    unittest.main()
