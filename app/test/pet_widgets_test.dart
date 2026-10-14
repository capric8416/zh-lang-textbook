import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zh_textbook/models/pet.dart';
import 'package:zh_textbook/models/pet_mission.dart';
import 'package:zh_textbook/models/practice.dart';
import 'package:zh_textbook/models/quick_practice.dart';
import 'package:zh_textbook/services/learning_mastery.dart';
import 'package:zh_textbook/widgets/pet_celebration.dart';
import 'package:zh_textbook/widgets/pet_growth_card.dart';
import 'package:zh_textbook/widgets/pet_interaction_stage.dart';
import 'package:zh_textbook/widgets/pet_quick_reaction.dart';
import 'package:zh_textbook/widgets/pet_practice_companion.dart';
import 'package:zh_textbook/widgets/pet_room_scene.dart';

void main() {
  test('正式互动动画仍覆盖 14 种状态并复用 8 个 WebP', () {
    expect(PetInteractionCue.values, hasLength(14));
    expect(
      PetInteractionCue.values.map(petAnimationAsset).toSet(),
      hasLength(8),
    );
  });

  test('三花猫按完整的互动状态集引用对应动画资源', () {
    final assets = PetInteractionCue.values
        .map((cue) => petAnimationAsset(cue, species: PetSpecies.cat))
        .toSet();
    expect(assets, {
      'assets/images/cat/san_hua/idle.webp',
      'assets/images/cat/san_hua/invite.webp',
      'assets/images/cat/san_hua/think.webp',
      'assets/images/cat/san_hua/celebrate.webp',
      'assets/images/cat/san_hua/encourage.webp',
      'assets/images/cat/san_hua/gift.webp',
      'assets/images/cat/san_hua/happy.webp',
      'assets/images/cat/san_hua/study.webp',
    });
  });

  testWidgets('房间横屏和竖屏保持宠物尺寸及地板比例', (tester) async {
    Future<void> pumpRoom(Size size) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: size.width,
              height: size.height,
              child: const PetRoomScene(profile: PetProfile()),
            ),
          ),
        ),
      ),
    );

    await pumpRoom(const Size(400, 258));
    final portraitRoom = tester.getSize(
      find.byKey(const ValueKey('pet-room-living-room')),
    );
    final portraitPet = tester.getSize(
      find.byKey(const ValueKey('pet-live-animation-repeat')),
    );
    final portraitFloor = tester.getSize(
      find.byKey(const ValueKey('pet-room-floor')),
    );

    await pumpRoom(const Size(1000, 645));
    final landscapeRoom = tester.getSize(
      find.byKey(const ValueKey('pet-room-living-room')),
    );
    final landscapePet = tester.getSize(
      find.byKey(const ValueKey('pet-live-animation-repeat')),
    );
    final landscapeFloor = tester.getSize(
      find.byKey(const ValueKey('pet-room-floor')),
    );

    expect(
      landscapePet.width / landscapeRoom.width,
      closeTo(portraitPet.width / portraitRoom.width, 0.01),
    );
    expect(
      landscapeFloor.height / landscapeRoom.height,
      closeTo(portraitFloor.height / portraitRoom.height, 0.01),
    );
  });

  testWidgets('宠物房间会按激活家具播放台灯书柜和花盆动画', (tester) async {
    final cases = [
      (room: 'study-room', furniture: 'desk-lamp', cue: PetInteractionCue.lamp),
      (
        room: 'study-room',
        furniture: 'bookcase',
        cue: PetInteractionCue.bookcase,
      ),
      (room: 'yard', furniture: 'flower-pot', cue: PetInteractionCue.flowerPot),
    ];
    for (final testCase in cases) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PetRoomScene(
              profile: PetProfile(
                selectedRoom: testCase.room,
                unlockedFurniture: {testCase.furniture},
                furnitureStates: {
                  testCase.furniture: FurnitureVisualState.active,
                },
              ),
            ),
          ),
        ),
      );
      expect(
        find.byKey(ValueKey('pet-live-animation-${testCase.cue.name}')),
        findsOneWidget,
      );
    }
  });

  testWidgets('成长卡显示全局成长和下一课进度', (tester) async {
    var invited = false;
    final lesson = LessonMastery(
      chapterId: 'chapter-1',
      chapterName: '找春天',
      questions: [
        for (var index = 0; index < 5; index++) _question('question-$index'),
      ],
      masteredQuestionIds: const {'question-0', 'question-1', 'question-2'},
    );
    final mastery = TextbookMastery([
      UnitMastery(unitId: 'unit-1', unitName: '第一单元', lessons: [lesson]),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PetGrowthCard(
            profile: const PetProfile(
              name: '豆豆',
              growthPoints: 180,
              majorStage: 2,
            ),
            mastery: mastery,
            goal: '再掌握 2 道题，小台灯就会解锁！',
            invitation: '豆豆想陪你轻松练三题',
            onAcceptInvitation: () => invited = true,
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('pet-growth-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('pet-avatar')), findsOneWidget);
    expect(find.text('成长值 180'), findsOneWidget);
    expect(find.text('大阶段 2'), findsOneWidget);
    expect(find.text('豆豆 · 小狗（黄狗白面）'), findsOneWidget);
    expect(find.textContaining('小台灯'), findsOneWidget);
    expect(find.textContaining('找春天  3/5（60%）'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pet-practice-invitation')));
    expect(invited, isTrue);
  });

  testWidgets('庆祝动画先显示课文反应再显示单元礼花', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: _CelebrationHarness(
          petName: '豆豆',
          celebrations: [
            PetCelebration.lesson(title: '找春天', threshold: 80),
            PetCelebration.unit(unitName: '第一单元'),
          ],
        ),
      ),
    );

    await tester.tap(find.text('庆祝'));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('pet-lesson-celebration')),
      findsOneWidget,
    );
    expect(find.text('80% 达成！'), findsOneWidget);
    expect(find.text('豆豆也来庆祝！'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('pet-live-animation-lessonCelebration')),
      findsOneWidget,
    );

    await tester.pump(const Duration(milliseconds: 2200));
    await tester.pump();
    expect(find.byKey(const ValueKey('pet-unit-celebration')), findsOneWidget);
    expect(find.text('单元大阶段通关！'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('pet-live-animation-unitCelebration')),
      findsOneWidget,
    );

    await tester.pump(const Duration(milliseconds: 2700));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pet-unit-celebration')), findsNothing);
  });

  testWidgets('减少动态效果时使用短暂静态反馈', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: _CelebrationHarness(
            celebrations: [PetCelebration.lesson(title: '找春天', threshold: 100)],
          ),
        ),
      ),
    );

    await tester.tap(find.text('庆祝'));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('pet-lesson-celebration')),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 750));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pet-lesson-celebration')), findsNothing);
  });

  testWidgets('普通三题完成显示短暂宠物动作反馈', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _QuickReactionHarness()));

    await tester.tap(find.text('完成三题'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const ValueKey('pet-quick-reaction')), findsOneWidget);
    expect(find.textContaining('叼来一朵小花'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('pet-live-animation-flowerGift')),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 2));
    expect(find.byKey(const ValueKey('pet-quick-reaction')), findsNothing);
  });

  testWidgets('三题中宠物显示思考、鼓励和任务进度', (tester) async {
    final mission = PetCompanionMission.forQuickPractice(
      action: QuickPracticeAction.characters,
      petName: '豆豆',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PetPracticeCompanion(
            profile: const PetProfile(name: '豆豆'),
            mission: mission,
            mood: PetPracticeMood.thinking,
            completedSteps: 0,
            action: PetActionKind.think,
          ),
        ),
      ),
    );
    expect(find.textContaining('慢慢想'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('pet-live-animation-think')),
      findsOneWidget,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PetPracticeCompanion(
            profile: const PetProfile(name: '豆豆'),
            mission: mission,
            mood: PetPracticeMood.encourage,
            completedSteps: 1,
            action: PetActionKind.incorrect,
          ),
        ),
      ),
    );
    expect(find.textContaining('继续试'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('pet-live-animation-incorrect')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<LinearProgressIndicator>(
            find.byKey(const ValueKey('pet-mission-progress')),
          )
          .value,
      closeTo(1 / 3, 0.001),
    );
  });

  testWidgets('减少动态效果时答对反馈使用零时长缩放', (tester) async {
    final mission = PetCompanionMission.forQuickPractice(
      action: QuickPracticeAction.mixedReview,
      petName: '豆豆',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: PetPracticeCompanion(
              profile: const PetProfile(name: '豆豆'),
              mission: mission,
              mood: PetPracticeMood.celebrate,
              completedSteps: 2,
            ),
          ),
        ),
      ),
    );
    expect(find.textContaining('答对啦'), findsOneWidget);
    expect(
      tester.widget<AnimatedScale>(find.byType(AnimatedScale)).duration,
      Duration.zero,
    );
  });

  testWidgets('任务完成可自愿再练也可正常返回', (tester) async {
    bool? result;
    final mission = PetCompanionMission.forQuickPractice(
      action: QuickPracticeAction.mixedReview,
      petName: '豆豆',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () async {
              result = await showDialog<bool>(
                context: context,
                barrierDismissible: false,
                builder: (_) => PetMissionCompletionDialog(
                  profile: const PetProfile(name: '豆豆'),
                  mission: mission,
                ),
              );
            },
            child: const Text('完成'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(find.text('再练三题'), findsOneWidget);
    expect(find.textContaining('豆豆叼来一朵小花'), findsOneWidget);
    expect(find.byKey(const ValueKey('pet-action-complete')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('pet-live-animation-complete')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('repeat-quick-practice')));
    await tester.pump();
    expect(find.byKey(const ValueKey('pet-action-repeat')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('pet-live-animation-repeat')),
      findsOneWidget,
    );
    await tester.pumpAndSettle();
    expect(result, isTrue);

    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('先回去看看'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });
}

class _CelebrationHarness extends StatelessWidget {
  const _CelebrationHarness({required this.celebrations, this.petName = '小语'});

  final List<PetCelebration> celebrations;
  final String petName;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: FilledButton(
        onPressed: () => unawaited(
          showPetCelebrations(context, celebrations, petName: petName),
        ),
        child: const Text('庆祝'),
      ),
    ),
  );
}

class _QuickReactionHarness extends StatelessWidget {
  const _QuickReactionHarness();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: FilledButton(
        onPressed: () => showPetQuickReaction(
          context,
          profile: const PetProfile(name: '豆豆'),
          action: QuickPracticeAction.readAloud,
        ),
        child: const Text('完成三题'),
      ),
    ),
  );
}

PracticeQuestion _question(String id) => PracticeQuestion(
  id: id,
  kind: '词语',
  category: '词',
  answerLines: const ['春天'],
  promptLines: const ['chūn tiān'],
  source: '测试',
  chapterId: 'chapter-1',
);
