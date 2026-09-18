import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zh_textbook/models/pet.dart';
import 'package:zh_textbook/models/pet_mission.dart';
import 'package:zh_textbook/models/practice.dart';
import 'package:zh_textbook/models/quick_practice.dart';
import 'package:zh_textbook/models/textbook.dart';
import 'package:zh_textbook/services/learning_mastery.dart';
import 'package:zh_textbook/services/pet_growth.dart';
import 'package:zh_textbook/services/pet_companion.dart';
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
    expect(legacy.name, defaultPetName);
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
    expect(await store.rename('  小 春  '), isTrue);
    expect(await store.rename('   '), isFalse);
    final reopened = await PetGrowthStore.open();
    expect(reopened.profile.breed, 'shiba');
    expect(reopened.profile.selectedDecoration, 'blue-collar');
    expect(reopened.profile.selectedRoom, 'study-room');
    expect(reopened.profile.name, '小 春');
  });

  test('陪伴引导显示下一解锁并优先邀请整理错题', () {
    final questions = [
      _question('first-0', firstChapterId),
      _question('first-1', firstChapterId),
      _question('first-2', firstChapterId),
    ];
    final progress = PracticeProgress({
      questions.first.attemptId(PracticeDirection.writeHanzi):
          const QuestionProgress(wrongCount: 1),
    });
    final mastery = calculateTextbookMastery(
      textbook: textbook,
      catalog: PracticeCatalog(questions),
      progress: progress,
    );
    final guide = PetCompanionGuide.build(
      profile: const PetProfile(
        name: '豆豆',
        unlockedFurniture: {'pet-bed', 'study-desk', 'shade-tree'},
      ),
      mastery: mastery,
      catalog: PracticeCatalog(questions),
      progress: progress,
    );

    expect(guide.goal, contains('小台灯'));
    expect(guide.goal, contains('2 道题'));
    expect(guide.invitation?.message, '豆豆想和你一起整理三个错题');
    expect(guide.invitation?.action, QuickPracticeAction.mistakeFirst);
  });

  test('三题任务按来源确定家具且始终包含三个步骤', () {
    final invited = PetCompanionMission.forQuickPractice(
      action: QuickPracticeAction.readAloud,
      petName: '豆豆',
    );
    final furniture = PetCompanionMission.forQuickPractice(
      action: QuickPracticeAction.mixedReview,
      petName: '豆豆',
      furnitureId: 'desk-lamp',
    );

    expect(invited.kind, PetMissionKind.bloomFlower);
    expect(invited.targetFurnitureId, 'flower-pot');
    expect(invited.source, PetMissionSource.invitation);
    expect(invited.steps, hasLength(3));
    expect(furniture.kind, PetMissionKind.lightLamp);
    expect(furniture.targetFurnitureId, 'desk-lamp');
    expect(furniture.source, PetMissionSource.furniture);
  });

  test('旧档案补齐家具状态但不重放历史解锁提示', () {
    final legacy = PetProfile.fromJson({
      'major_stage': 1,
      'unlocked_furniture': ['pet-bed', 'study-desk', 'shade-tree'],
    });
    expect(legacy.furnitureStateInitialized, isFalse);

    final result = PetGrowthEngine.synchronize(
      profile: legacy,
      textbookKey: 'grade2b',
      textbook: textbook,
      catalog: const PracticeCatalog([]),
      progress: const PracticeProgress({}),
      emitCelebrations: false,
    );
    expect(result.profile.furnitureStateInitialized, isTrue);
    expect(result.profile.pendingFurnitureReveals, isEmpty);
    expect(
      result.profile.furnitureState('desk-lamp'),
      FurnitureVisualState.ready,
    );
  });

  test('新家具只标记一次并可激活和确认展示', () async {
    final first = PetGrowthEngine.synchronize(
      profile: const PetProfile(),
      textbookKey: 'grade2b',
      textbook: textbook,
      catalog: const PracticeCatalog([]),
      progress: const PracticeProgress({}),
      emitCelebrations: false,
    );
    expect(first.profile.pendingFurnitureReveals, contains('study-desk'));
    final repeated = PetGrowthEngine.synchronize(
      profile: first.profile,
      textbookKey: 'grade2b',
      textbook: textbook,
      catalog: const PracticeCatalog([]),
      progress: const PracticeProgress({}),
      emitCelebrations: false,
    );
    expect(
      repeated.profile.pendingFurnitureReveals,
      first.profile.pendingFurnitureReveals,
    );

    SharedPreferences.setMockInitialValues({
      'pet_growth_profile': jsonEncode({
        'version': 5,
        'profile': first.profile.toJson(),
      }),
    });
    final store = await PetGrowthStore.open();
    expect(await store.activateFurniture('study-desk', 'fillBookcase'), isTrue);
    expect(
      store.profile.furnitureState('study-desk'),
      FurnitureVisualState.active,
    );
    expect(store.profile.lastMissionKind, 'fillBookcase');
    expect(await store.acknowledgeFurnitureReveal('study-desk'), isTrue);
    expect(
      store.profile.pendingFurnitureReveals,
      isNot(contains('study-desk')),
    );
  });

  test('回访只将相邻日识别为次日且忽略时钟回拨', () async {
    final store = await PetGrowthStore.open();
    expect(
      await store.recordVisit(DateTime(2026, 9, 17, 8)),
      PetVisitTransition.neutral,
    );
    expect(
      await store.recordVisit(DateTime(2026, 9, 17, 20)),
      PetVisitTransition.sameDay,
    );
    expect(
      await store.recordVisit(DateTime(2026, 9, 18, 8)),
      PetVisitTransition.nextDay,
    );
    expect(
      await store.recordVisit(DateTime(2026, 9, 16, 8)),
      PetVisitTransition.neutral,
    );
    expect(store.profile.lastVisitDate, '2026-09-18');
  });

  test('每日位置同日稳定且问候不包含断签压力', () {
    final first = PetDailyCompanion.build(
      profile: const PetProfile(name: '豆豆'),
      anonymousInstallId: 'install',
      date: DateTime(2026, 9, 18, 8),
    );
    final repeated = PetDailyCompanion.build(
      profile: const PetProfile(name: '豆豆'),
      anonymousInstallId: 'install',
      date: DateTime(2026, 9, 18, 22),
    );
    expect(repeated.alignmentX, first.alignmentX);
    expect(repeated.greeting, first.greeting);
    expect(first.greeting, isNot(contains('错过')));
    expect(first.greeting, isNot(contains('断签')));
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
