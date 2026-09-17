import 'package:flutter_test/flutter_test.dart';
import 'package:zh_textbook/models/practice.dart';
import 'package:zh_textbook/models/quick_practice.dart';
import 'package:zh_textbook/services/practice_progress.dart';
import 'package:zh_textbook/services/quick_practice.dart';

void main() {
  group('QuickPracticeSelector', () {
    test('错题优先会先选择三个当前错题', () {
      final catalog = PracticeCatalog([
        _question('a'),
        _question('b'),
        _question('c'),
      ]);
      final progress = PracticeProgress({
        'a:writeHanzi': const QuestionProgress(wrongCount: 1),
        'b:writePinyin': const QuestionProgress(wrongCount: 1),
        'c:writeHanzi': const QuestionProgress(wrongCount: 2),
      });

      final result = QuickPracticeSelector.select(
        catalog: catalog,
        progress: progress,
        action: QuickPracticeAction.mistakeFirst,
      );

      expect(result.isAvailable, isTrue);
      expect(result.session!.attempts.map((item) => item.attemptId), [
        'a:writeHanzi',
        'b:writePinyin',
        'c:writeHanzi',
      ]);
    });

    test('汉字家具优先选择写汉字和写拼音方向', () {
      final result = QuickPracticeSelector.select(
        catalog: PracticeCatalog([
          _question('a', category: '词', answer: '春风'),
          _question('b', category: '词', answer: '花朵'),
        ]),
        progress: const PracticeProgress({}),
        action: QuickPracticeAction.characters,
      );

      expect(result.session, isNotNull);
      expect(
        result.session!.attempts.every(
          (item) =>
              item.direction == PracticeDirection.writeHanzi ||
              item.direction == PracticeDirection.writePinyin,
        ),
        isTrue,
      );
    });

    test('朗读偏好不足三题时从同一本教材补足', () {
      final result = QuickPracticeSelector.select(
        catalog: PracticeCatalog([
          _question('word', category: '词', answer: '春风'),
          _question('character'),
        ]),
        progress: const PracticeProgress({}),
        action: QuickPracticeAction.readAloud,
      );

      expect(result.session, isNotNull);
      expect(result.session!.attempts, hasLength(3));
      expect(result.session!.attempts.first.attemptId, 'word:readAloud');
      expect(
        result.session!.attempts.map((item) => item.questionId).toSet(),
        isNot(contains('another-textbook')),
      );
    });

    test('当前教材不足三个可用作答方向时返回不可用', () {
      final result = QuickPracticeSelector.select(
        catalog: PracticeCatalog([_question('only')]),
        progress: const PracticeProgress({}),
        action: QuickPracticeAction.mixedReview,
      );

      expect(result.isAvailable, isFalse);
      expect(result.reason, contains('不足 3 题'));
    });

    test('选择结果只包含传入的当前教材题目', () {
      final catalog = PracticeCatalog([
        _question('current-a'),
        _question('current-b'),
      ]);

      final result = QuickPracticeSelector.select(
        catalog: catalog,
        progress: const PracticeProgress({}),
        action: QuickPracticeAction.mixedReview,
      );

      expect(result.session, isNotNull);
      expect(
        result.session!.attempts.map((item) => item.questionId).toSet(),
        everyElement(startsWith('current-')),
      );
    });
  });
}

PracticeQuestion _question(
  String id, {
  String category = '字',
  String answer = '春',
}) => PracticeQuestion(
  id: id,
  kind: '测试',
  category: category,
  answerLines: [answer],
  promptLines: [answer == '春' ? 'chūn' : 'chūn fēng'],
  source: '当前教材',
  chapterId: 'chapter-1',
);
