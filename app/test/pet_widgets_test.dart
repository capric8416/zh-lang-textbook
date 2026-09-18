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
import 'package:zh_textbook/widgets/pet_quick_reaction.dart';
import 'package:zh_textbook/widgets/pet_practice_companion.dart';

void main() {
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
    expect(find.text('豆豆 · 小狗'), findsOneWidget);
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

    await tester.pump(const Duration(milliseconds: 2200));
    await tester.pump();
    expect(find.byKey(const ValueKey('pet-unit-celebration')), findsOneWidget);
    expect(find.text('单元大阶段通关！'), findsOneWidget);

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
          ),
        ),
      ),
    );
    expect(find.textContaining('慢慢想'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PetPracticeCompanion(
            profile: const PetProfile(name: '豆豆'),
            mission: mission,
            mood: PetPracticeMood.encourage,
            completedSteps: 1,
          ),
        ),
      ),
    );
    expect(find.textContaining('继续试'), findsOneWidget);
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
                builder: (_) =>
                    PetMissionCompletionDialog(petName: '豆豆', mission: mission),
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
    expect(find.textContaining('豆豆想问'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('repeat-quick-practice')));
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
