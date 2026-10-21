import 'package:flutter_test/flutter_test.dart';
import 'package:zh_textbook/services/student_learning_history.dart';

void main() {
  test(
    'remote records confirm upload and override local duplicates across all classes',
    () {
      final records = StudentLearningHistory.merge(
        'a',
        [
          {'id': 'one', 'studentId': 'a', 'studentAnswer': 'local'},
        ],
        [
          {'id': 'one', 'studentId': 'a'},
          {'id': 'pending', 'studentId': 'a'},
        ],
        [],
        remote: [
          {
            'id': 'one',
            'studentId': 'a',
            'studentAnswer': 'server',
            'classId': 'old-class',
          },
          {'id': 'no-class', 'studentId': 'a', 'classId': null},
          {'id': 'foreign', 'studentId': 'b'},
        ],
      );
      expect(records.length, 3);
      final byId = {for (final r in records) r.text('id'): r};
      expect(byId['one']!.text('studentAnswer'), 'server');
      expect(byId['one']!.syncState, AttemptSyncState.uploaded);
      expect(byId['no-class']!.syncState, AttemptSyncState.uploaded);
      expect(byId['pending']!.syncState, AttemptSyncState.pending);
    },
  );
  Map<String, Object?> attempt(
    String id, {
    String student = 'a',
    String? time,
  }) => {
    'id': id,
    'studentId': student,
    'occurredAt': time ?? '2026-10-21T10:00:00Z',
    'prompt': '题目',
    'studentAnswer': '作答',
    'expectedAnswer': '答案',
    'isCorrect': true,
  };

  test(
    'only own attempts are shown, queue duplicates merge and old queued attempts remain visible',
    () {
      final result = StudentLearningHistory.merge(
        'a',
        [attempt('one'), attempt('foreign', student: 'b')],
        [
          attempt('one'),
          attempt('older-queue'),
          attempt('foreign-queue', student: 'b'),
        ],
        [],
      );
      expect(result.map((r) => r.text('id')).toSet(), {'one', 'older-queue'});
      expect(
        result.every((r) => r.syncState == AttemptSyncState.pending),
        isTrue,
      );
      expect(result.first.text('studentAnswer'), '作答');
    },
  );

  test('only a server receipt proves upload; removal from queue does not', () {
    final result = StudentLearningHistory.merge(
      'a',
      [attempt('confirmed'), attempt('unknown'), attempt('queued')],
      [attempt('confirmed'), attempt('queued')],
      [
        {'id': 'confirmed'},
      ],
    );
    final states = {for (final r in result) r.text('id'): r.syncState};
    expect(states['confirmed'], AttemptSyncState.uploaded);
    expect(states['unknown'], AttemptSyncState.unknown);
    expect(states['queued'], AttemptSyncState.pending);
  });

  test('sort by actual time across offsets; malformed dates go last', () {
    final result = StudentLearningHistory.merge(
      'a',
      [
        attempt('older', time: '2026-10-21T12:00:00+08:00'),
        attempt('newer', time: '2026-10-21T10:00:00Z'),
        attempt('invalid', time: 'bad-date'),
      ],
      [],
      [],
    );
    expect(result.map((r) => r.text('id')), ['newer', 'older', 'invalid']);
  });
}
