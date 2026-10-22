import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zh_textbook/models/practice.dart';
import 'package:zh_textbook/services/practice_progress.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<PracticeProgressStore> openStore(String textbookKey) =>
      PracticeProgressStore.open(textbookKey, namespace: 'test-account');

  test('每道题记录对错次数和最近时间', () async {
    final store = await openStore('grade2b');

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
    final store = await openStore('grade2b');
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
    final first = await openStore('grade2a');
    await first.record('question-1:writeHanzi', correct: true);

    final second = await openStore('grade2b');
    expect(second.progress.completedCount, 0);
  });

  test('曾经答错的题需跨至少24小时再次答对才移出专项', () async {
    final store = await openStore('grade2b');
    const attemptId = 'question-1:writeHanzi';
    final firstAttempt = DateTime.utc(2026, 10, 20, 8);

    await store.recordAt(attemptId, correct: false, occurredAt: firstAttempt);
    expect(store.progress.forQuestion(attemptId).isWrong, isTrue);

    await store.recordAt(
      attemptId,
      correct: true,
      occurredAt: firstAttempt.add(const Duration(minutes: 1)),
    );
    expect(store.progress.forQuestion(attemptId).isWrong, isTrue);
    expect(store.progress.wrongCount, 1);

    await store.recordAt(
      attemptId,
      correct: true,
      occurredAt: firstAttempt.add(const Duration(hours: 25)),
    );
    expect(store.progress.forQuestion(attemptId).isWrong, isFalse);
    expect(store.progress.wrongCount, 0);
  });

  test('练习方向按连续正确和24小时巩固计算掌握阶段', () async {
    final store = await openStore('grade2b');
    const attemptId = 'question-1:writeHanzi';
    final firstAttempt = DateTime.utc(2026, 10, 20, 8);

    await store.recordAt(attemptId, correct: true, occurredAt: firstAttempt);
    expect(
      store.progress.forQuestion(attemptId).masteryStage,
      QuestionMasteryStage.initial,
    );

    await store.recordAt(
      attemptId,
      correct: true,
      occurredAt: firstAttempt.add(const Duration(hours: 23, minutes: 59)),
    );
    expect(
      store.progress.forQuestion(attemptId).masteryStage,
      QuestionMasteryStage.initial,
    );

    await store.recordAt(
      attemptId,
      correct: true,
      occurredAt: firstAttempt.add(const Duration(hours: 24)),
    );
    expect(
      store.progress.forQuestion(attemptId).masteryStage,
      QuestionMasteryStage.stable,
    );
    final reopened = await openStore('grade2b');
    expect(
      reopened.progress.forQuestion(attemptId).masteryStage,
      QuestionMasteryStage.stable,
    );

    await store.recordAt(
      attemptId,
      correct: false,
      occurredAt: firstAttempt.add(const Duration(hours: 25)),
    );
    expect(
      store.progress.forQuestion(attemptId).masteryStage,
      QuestionMasteryStage.needsReinforcement,
    );
    expect(store.progress.forQuestion(attemptId).isWrong, isTrue);

    await store.recordAt(
      attemptId,
      correct: true,
      occurredAt: firstAttempt.add(const Duration(hours: 26)),
    );
    expect(
      store.progress.forQuestion(attemptId).masteryStage,
      QuestionMasteryStage.initial,
    );
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
