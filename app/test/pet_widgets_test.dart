import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zh_textbook/models/pet.dart';
import 'package:zh_textbook/models/practice.dart';
import 'package:zh_textbook/services/learning_mastery.dart';
import 'package:zh_textbook/widgets/pet_celebration.dart';
import 'package:zh_textbook/widgets/pet_growth_card.dart';

void main() {
  testWidgets('成长卡显示全局成长和下一课进度', (tester) async {
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
            profile: const PetProfile(growthPoints: 180, majorStage: 2),
            mastery: mastery,
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('pet-growth-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('pet-avatar')), findsOneWidget);
    expect(find.text('成长值 180'), findsOneWidget);
    expect(find.text('大阶段 2'), findsOneWidget);
    expect(find.textContaining('找春天  3/5（60%）'), findsOneWidget);
  });

  testWidgets('庆祝动画先显示课文反应再显示单元礼花', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: _CelebrationHarness(
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
}

class _CelebrationHarness extends StatelessWidget {
  const _CelebrationHarness({required this.celebrations});

  final List<PetCelebration> celebrations;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: FilledButton(
        onPressed: () => unawaited(showPetCelebrations(context, celebrations)),
        child: const Text('庆祝'),
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
