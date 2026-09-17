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

  test('四种练习方向独立记录', () async {
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
    expect(
      store.progress
          .forQuestion(question.attemptId(PracticeDirection.listenWriteHanzi))
          .totalCount,
      0,
    );
    expect(
      store.progress
          .forQuestion(question.attemptId(PracticeDirection.readAloud))
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

  test('错题在正确次数严格超过错误次数三倍后移出专项', () async {
    final store = await PracticeProgressStore.open('grade2b');
    const attemptId = 'question-1:writeHanzi';

    await store.record(attemptId, correct: false);
    expect(store.progress.forQuestion(attemptId).isWrong, isTrue);

    for (var count = 0; count < 3; count++) {
      await store.record(attemptId, correct: true);
    }
    expect(store.progress.forQuestion(attemptId).isWrong, isTrue);
    expect(store.progress.wrongCount, 1);

    await store.record(attemptId, correct: true);
    expect(store.progress.forQuestion(attemptId).isWrong, isFalse);
    expect(store.progress.wrongCount, 0);
  });

  test('错题数只统计当前题库支持的题目和练习方向', () {
    const singleCharacterQuestion = PracticeQuestion(
      id: 'question-1',
      kind: '字',
      category: '字',
      answerLines: ['长'],
      promptLines: ['cháng'],
      source: '课文',
      chapterId: 'chapter-1',
    );
    const progress = PracticeProgress({
      'removed-question:writeHanzi': QuestionProgress(wrongCount: 1),
      'question-1:readAloud': QuestionProgress(wrongCount: 1),
      'question-1:writeHanzi': QuestionProgress(wrongCount: 1),
    });

    expect(progress.wrongCount, 3);
    expect(progress.wrongCountFor([singleCharacterQuestion]), 1);
  });
}
