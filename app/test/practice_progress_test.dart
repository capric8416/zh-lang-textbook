import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zh_textbook/models/practice.dart';
import 'package:zh_textbook/services/practice_progress.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('每道题记录对错次数和最近时间', () async {
    final store = await PracticeProgressStore.open('grade2b');

    await store.record('question-1:writeHanzi', correct: true);
    expect(store.isBlocked('question-1:writeHanzi', DateTime.now()), isTrue);
    await store.record('question-1:writeHanzi', correct: false);

    final progress = store.progress.forQuestion('question-1:writeHanzi');
    expect(progress.correctCount, 1);
    expect(progress.wrongCount, 1);
    expect(progress.lastCorrectAt, isNotNull);
    expect(progress.lastWrongAt, isNotNull);
  });

  test('两种练习方向独立记录', () async {
    final store = await PracticeProgressStore.open('grade2b');
    const question = PracticeQuestion(
      id: 'question-1',
      kind: '字',
      category: '字',
      answerLines: ['春'],
      promptLines: ['chūn'],
      source: '找春天',
      chapterId: 'u01-reading-02',
    );

    await store.record(
      question.attemptId(PracticeDirection.writeHanzi),
      correct: true,
    );

    expect(
      store.progress
          .forQuestion(question.attemptId(PracticeDirection.writeHanzi))
          .correctCount,
      1,
    );
    expect(
      store.progress
          .forQuestion(question.attemptId(PracticeDirection.writePinyin))
          .totalCount,
      0,
    );
  });

  test('不同教材的练习进度不混用', () async {
    final first = await PracticeProgressStore.open('grade2a');
    await first.record('question-1:writeHanzi', correct: true);

    final second = await PracticeProgressStore.open('grade2b');
    expect(second.progress.completedCount, 0);
  });
}
