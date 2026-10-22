import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zh_textbook/models/practice.dart';
import 'package:zh_textbook/models/quick_practice.dart';
import 'package:zh_textbook/services/practice_progress.dart';
import 'package:zh_textbook/services/practice_scheduler.dart';
import 'package:zh_textbook/services/quick_practice.dart';

void main() {
  final start = DateTime.utc(2026, 10, 22, 8);
  const id = 'q:writeHanzi';
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('订正后等待24小时，重复正确不延后，到期稳定后隔7天复习', () async {
    final store = await PracticeProgressStore.open('book', namespace: 'test');
    await store.recordAt(id, correct: false, occurredAt: start);
    expect(store.isBlocked(id, start), isFalse);
    final corrected = start.add(const Duration(minutes: 1));
    await store.recordAt(id, correct: true, occurredAt: corrected);
    final due = corrected.add(const Duration(hours: 24));
    await store.recordAt(
      id,
      correct: true,
      occurredAt: corrected.add(const Duration(hours: 1)),
    );
    var record = store.progress.forQuestion(id);
    expect(record.reviewDueAt!.toUtc(), due);
    expect(
      record.isAvailableAt(due.subtract(const Duration(microseconds: 1))),
      isFalse,
    );
    expect(record.isAvailableAt(due), isTrue);
    expect(record.isWrong, isTrue);
    await store.recordAt(id, correct: true, occurredAt: due);
    record = store.progress.forQuestion(id);
    expect(record.isWrong, isFalse);
    expect(record.reviewDueAt!.toUtc(), due.add(const Duration(days: 7)));
    expect(
      record.selectionWeight(due.add(const Duration(days: 7))),
      lessThan(const QuestionProgress().selectionWeight(due)),
    );
    await store.recordAt(
      id,
      correct: false,
      occurredAt: due.add(const Duration(minutes: 1)),
    );
    expect(store.isBlocked(id, due.add(const Duration(minutes: 1))), isFalse);
  });

  test('旧版暂缓字段不阻止订正，历史错题次数不造成无限权重', () {
    final record = QuestionProgress.fromJson({
      'wrong_count': 100,
      'last_wrong_at': start.toIso8601String(),
      'blocked_until': start.add(const Duration(days: 200)).toIso8601String(),
      'skip_until': start.add(const Duration(days: 200)).toIso8601String(),
      'skip_remaining': 100,
    });
    expect(record.isAvailableAt(start), isTrue);
    expect(
      record.selectionWeight(start),
      const QuestionProgress(wrongCount: 1).selectionWeight(start),
    );
  });

  test('综合和专项都不选等待巩固的题，其他可练方向优先于刚做过的方向', () {
    final waiting = QuestionProgress(
      correctCount: 1,
      wrongCount: 1,
      lastCorrectAt: start,
      correctStreakStartedAt: start,
    );
    final progress = PracticeProgress({
      'a:writeHanzi': waiting,
      'a:writePinyin': waiting,
      'b:writeHanzi': const QuestionProgress(wrongCount: 2),
      'b:writePinyin': const QuestionProgress(wrongCount: 1),
    });
    for (final mistakesOnly in [false, true]) {
      final selected = PracticeScheduler.select(
        questions: [_question('a'), _question('b')],
        progress: progress,
        mistakesOnly: mistakesOnly,
        now: start,
        random: Random(1),
        previousAttemptId: 'b:writeHanzi',
      );
      expect(selected!.question.attemptId(selected.direction), 'b:writePinyin');
      expect(
        PracticeScheduler.select(
          questions: [_question('a')],
          progress: progress,
          mistakesOnly: mistakesOnly,
          now: start,
          random: Random(1),
        ),
        isNull,
      );
    }
  });

  test('三题陪练也排除等待订正，优先到期巩固且不足时不强行补题', () {
    final waiting = QuestionProgress(
      correctCount: 1,
      wrongCount: 2,
      lastCorrectAt: start,
      correctStreakStartedAt: start,
    );
    final due = start.subtract(const Duration(hours: 24));
    final progress = PracticeProgress({
      'a:writeHanzi': waiting,
      'a:writePinyin': waiting,
      'b:writeHanzi': QuestionProgress(
        correctCount: 1,
        lastCorrectAt: due,
        correctStreakStartedAt: due,
      ),
    });
    final selected = QuickPracticeSelector.select(
      catalog: PracticeCatalog([
        _question('a'),
        _question('b'),
        _question('c'),
      ]),
      progress: progress,
      action: QuickPracticeAction.mistakeFirst,
      now: start,
    );
    expect(selected.session!.attempts.first.attemptId, 'b:writeHanzi');
    expect(selected.session!.attempts.any((a) => a.questionId == 'a'), isFalse);
    expect(
      QuickPracticeSelector.select(
        catalog: PracticeCatalog([_question('a'), _question('b')]),
        progress: progress,
        action: QuickPracticeAction.mixedReview,
        now: start,
      ).isAvailable,
      isFalse,
    );
  });
}

PracticeQuestion _question(String id) => PracticeQuestion(
  id: id,
  kind: '字',
  category: '字',
  answerLines: const ['春'],
  promptLines: const ['chūn'],
  source: '测试',
  chapterId: 'chapter',
);
