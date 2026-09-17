import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zh_textbook/models/pet.dart';
import 'package:zh_textbook/models/practice.dart';
import 'package:zh_textbook/models/textbook.dart';
import 'package:zh_textbook/services/learning_mastery.dart';
import 'package:zh_textbook/services/pet_growth.dart';
import 'package:zh_textbook/services/practice_progress.dart';

void main() {
  late Textbook textbook;
  late String firstChapterId;
  late String secondChapterId;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    textbook = Textbook.fromJsonString(
      File(
        '../json_reviewed/zh-lang-grade2b-textbook-struct.json',
      ).readAsStringSync(),
    );
    final firstUnit = textbook.index.firstWhere(
      (unit) => unit.id != 'appendix' && unit.chapters.length >= 2,
    );
    firstChapterId = firstUnit.chapters[0].id;
    secondChapterId = firstUnit.chapters[1].id;
  });

  test('掌握度按唯一题目计算且不会因后续错误倒退', () {
    final questions = [
      for (var index = 0; index < 10; index++)
        _question('first-$index', firstChapterId),
      _question('second-0', secondChapterId),
    ];
    final progress = PracticeProgress({
      for (var index = 0; index < 6; index++)
        questions[index].attemptId(PracticeDirection.writeHanzi):
            const QuestionProgress(correctCount: 1, wrongCount: 2),
      questions[0].attemptId(PracticeDirection.writePinyin):
          const QuestionProgress(correctCount: 4),
    });

    final mastery = calculateTextbookMastery(
      textbook: textbook,
      catalog: PracticeCatalog(questions),
      progress: progress,
    );
    final firstLesson = mastery.lessons.firstWhere(
      (lesson) => lesson.chapterId == firstChapterId,
    );
    final secondLesson = mastery.lessons.firstWhere(
      (lesson) => lesson.chapterId == secondChapterId,
    );

    expect(firstLesson.masteredCount, 6);
    expect(firstLesson.percentage, 60);
    expect(firstLesson.reaches(60), isTrue);
    expect(firstLesson.reaches(80), isFalse);
    expect(secondLesson.percentage, 0);
    expect(
      mastery.units
          .firstWhere((unit) => unit.lessons.contains(firstLesson))
          .isComplete,
      isFalse,
    );
  });

  test('空课不阻止有题目的课完成单元', () {
    final questions = [
      for (var index = 0; index < 5; index++)
        _question('first-$index', firstChapterId),
    ];
    final progress = PracticeProgress({
      for (var index = 0; index < 3; index++)
        questions[index].attemptId(PracticeDirection.writeHanzi):
            const QuestionProgress(correctCount: 1),
    });
    final mastery = calculateTextbookMastery(
      textbook: textbook,
      catalog: PracticeCatalog(questions),
      progress: progress,
    );

    final unit = mastery.units.firstWhere(
      (candidate) =>
          candidate.lessons.any((lesson) => lesson.chapterId == firstChapterId),
    );
    expect(unit.eligibleLessons, hasLength(1));
    expect(unit.isComplete, isTrue);
  });

  test('同步奖励幂等并只展示最高课文阈值后再展示单元庆祝', () {
    final questions = [
      for (var index = 0; index < 10; index++)
        _question('first-$index', firstChapterId),
    ];
    final progress = PracticeProgress({
      for (final question in questions)
        question.attemptId(PracticeDirection.writeHanzi):
            const QuestionProgress(correctCount: 1),
    });
    final first = PetGrowthEngine.synchronize(
      profile: const PetProfile(),
      textbookKey: 'grade2b',
      textbook: textbook,
      catalog: PracticeCatalog(questions),
      progress: progress,
      emitCelebrations: true,
    );

    expect(first.profile.growthPoints, 300);
    expect(first.profile.majorStage, 1);
    expect(first.celebrations, hasLength(2));
    expect(first.celebrations[0].threshold, 100);
    expect(first.celebrations[1].type, PetCelebrationType.unit);

    final repeated = PetGrowthEngine.synchronize(
      profile: first.profile,
      textbookKey: 'grade2b',
      textbook: textbook,
      catalog: PracticeCatalog(questions),
      progress: progress,
      emitCelebrations: true,
    );
    expect(repeated.changed, isFalse);
    expect(repeated.celebrations, isEmpty);
    expect(repeated.profile.growthPoints, 300);

    final otherTextbook = PetGrowthEngine.synchronize(
      profile: repeated.profile,
      textbookKey: 'grade2a',
      textbook: textbook,
      catalog: PracticeCatalog(questions),
      progress: progress,
      emitCelebrations: false,
    );
    expect(otherTextbook.profile.growthPoints, 600);
    expect(otherTextbook.profile.majorStage, 2);
    expect(otherTextbook.celebrations, isEmpty);
  });

  test('全局宠物档案可持久化并静默回填', () async {
    final questions = [_question('first-0', firstChapterId)];
    final progress = PracticeProgress({
      questions.first.attemptId(PracticeDirection.writeHanzi):
          const QuestionProgress(correctCount: 1),
    });
    final store = await PetGrowthStore.open();
    final result = await store.synchronize(
      textbookKey: 'grade2b',
      textbook: textbook,
      catalog: PracticeCatalog(questions),
      progress: progress,
      emitCelebrations: false,
    );

    expect(result.celebrations, isEmpty);
    expect(result.profile.growthPoints, 210);
    expect(result.profile.majorStage, 1);

    final reopened = await PetGrowthStore.open();
    expect(reopened.profile.species, PetSpecies.dog);
    expect(reopened.profile.breed, 'default');
    expect(reopened.profile.growthPoints, 210);
    expect(reopened.profile.majorStage, 1);
  });

  test('课文阈值映射到逐步稀有的表情', () {
    expect(
      const PetCelebration.lesson(title: '课文', threshold: 60).expression,
      PetExpression.happy,
    );
    expect(
      const PetCelebration.lesson(title: '课文', threshold: 80).expression,
      PetExpression.wink,
    );
    expect(
      const PetCelebration.lesson(title: '课文', threshold: 90).expression,
      PetExpression.starry,
    );
    expect(
      const PetCelebration.lesson(title: '课文', threshold: 100).expression,
      PetExpression.radiant,
    );
  });

  test('v1 档案迁移出默认解锁并按阶段补齐解锁', () {
    final legacy = PetProfile.fromJson({
      'species': 'dog',
      'breed': 'default',
      'growth_points': 10,
      'major_stage': 2,
      'claimed_events': <String>[],
    });
    expect(legacy.unlockedBreeds, {'default'});
    final unlocked = PetGrowthEngine.breedsForStage(legacy.majorStage);
    expect(unlocked, containsAll(<String>['default', 'shiba', 'corgi']));
    expect(PetGrowthEngine.decorationsForStage(2), contains('red-scarf'));
    expect(legacy.selectedRoom, 'living-room');
    expect(legacy.unlockedFurniture, isEmpty);
    expect(
      PetGrowthEngine.furnitureForStage(2),
      containsAll(<String>[
        'pet-bed',
        'soft-rug',
        'toy-box',
        'study-desk',
        'desk-lamp',
        'shade-tree',
        'flower-pot',
      ]),
    );
  });

  test('宠物之家选择只允许已解锁项目并可持久化', () async {
    SharedPreferences.setMockInitialValues({
      'pet_growth_profile': jsonEncode({
        'version': 2,
        'profile': const PetProfile(
          majorStage: 1,
          unlockedBreeds: {'default', 'shiba'},
          unlockedDecorations: {'none', 'blue-collar'},
        ).toJson(),
      }),
    });
    final store = await PetGrowthStore.open();
    expect(await store.selectBreed('corgi'), isFalse);
    expect(await store.selectBreed('shiba'), isTrue);
    expect(await store.selectDecoration('blue-collar'), isTrue);
    expect(await store.selectRoom('unknown-room'), isFalse);
    expect(await store.selectRoom('study-room'), isTrue);
    final reopened = await PetGrowthStore.open();
    expect(reopened.profile.breed, 'shiba');
    expect(reopened.profile.selectedDecoration, 'blue-collar');
    expect(reopened.profile.selectedRoom, 'study-room');
  });
}

PracticeQuestion _question(String id, String chapterId) => PracticeQuestion(
  id: id,
  kind: '词语',
  category: '词',
  answerLines: const ['春天'],
  promptLines: const ['chūn tiān'],
  source: '测试',
  chapterId: chapterId,
);
