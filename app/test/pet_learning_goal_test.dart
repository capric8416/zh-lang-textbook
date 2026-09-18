import 'package:flutter_test/flutter_test.dart';
import 'package:zh_textbook/models/engagement_event.dart';
import 'package:zh_textbook/models/pet.dart';
import 'package:zh_textbook/models/pet_learning_goal.dart';
import 'package:zh_textbook/models/practice.dart';
import 'package:zh_textbook/models/quick_practice.dart';
import 'package:zh_textbook/services/learning_mastery.dart';
import 'package:zh_textbook/services/pet_companion.dart';
import 'package:zh_textbook/services/pet_invitation_scheduler.dart';
import 'package:zh_textbook/services/practice_progress.dart';

void main() {
  final questions = [
    for (var index = 0; index < 5; index++)
      PracticeQuestion(
        id: 'question-$index',
        kind: '词语',
        category: '词',
        answerLines: const ['春天'],
        promptLines: const ['chūn tiān'],
        source: '测试',
        chapterId: 'lesson-1',
      ),
  ];

  test('目标从现有掌握记录投影且不创建第二份计数', () {
    final mastery = TextbookMastery([
      UnitMastery(
        unitId: 'unit-1',
        unitName: '第一单元',
        lessons: [
          LessonMastery(
            chapterId: 'lesson-1',
            chapterName: '春天',
            questions: questions,
            masteredQuestionIds: const {'question-0', 'question-1'},
          ),
        ],
      ),
    ]);
    final progress = PracticeProgress({
      questions.first.attemptId(PracticeDirection.writeHanzi):
          const QuestionProgress(correctCount: 1),
    });
    final goal = PetLearningGoalProjector.primary(
      mastery: mastery,
      catalog: PracticeCatalog(questions),
      progress: progress,
    );

    expect(goal, isNotNull);
    expect(goal!.id, 'unit:unit-1:lesson:lesson-1');
    expect(goal.chapterIds, ['lesson-1']);
    expect(goal.current, 2);
    expect(goal.target, 3);
    expect(goal.remaining, 1);
    expect(goal.isComplete, isFalse);
    expect(goal.outcome, contains('台灯'));
  });

  test('先选第一个未完成单元，再选单元内剩余量最小的课文', () {
    final firstLarge = _questions('lesson-1', 5);
    final firstSmall = _questions('lesson-2', 5);
    final later = _questions('lesson-3', 5);
    final mastery = TextbookMastery([
      UnitMastery(
        unitId: 'unit-1',
        unitName: '第一单元',
        lessons: [
          _lesson(firstLarge, mastered: 0),
          _lesson(firstSmall, mastered: 2),
        ],
      ),
      UnitMastery(
        unitId: 'unit-2',
        unitName: '第二单元',
        lessons: [_lesson(later, mastered: 2)],
      ),
    ]);

    final goal = PetLearningGoalProjector.primary(
      mastery: mastery,
      catalog: PracticeCatalog([...firstLarge, ...firstSmall, ...later]),
      progress: const PracticeProgress({}),
    );

    expect(goal!.unitId, 'unit-1');
    expect(goal.chapterIds, ['lesson-2']);
    expect(goal.remaining, 1);
  });

  test('单元完成严格复用每课达到 60% 的语义', () {
    final passed = _questions('lesson-passed', 5);
    final incomplete = _questions('lesson-incomplete', 5);
    final unit = UnitMastery(
      unitId: 'unit-1',
      unitName: '第一单元',
      lessons: [_lesson(passed, mastered: 5), _lesson(incomplete, mastered: 1)],
    );
    expect(unit.isComplete, isFalse);

    final goal = PetLearningGoalProjector.primary(
      mastery: TextbookMastery([unit]),
      catalog: PracticeCatalog([...passed, ...incomplete]),
      progress: const PracticeProgress({}),
    );

    expect(goal, isNotNull);
    expect(goal!.chapterIds, ['lesson-incomplete']);
    expect(goal.current, 1);
    expect(goal.target, 3);
  });

  test('目标三题只使用目标课文且不回退到其他动作', () {
    final current = _questions('lesson-current', 3);
    final other = _questions('lesson-other', 3);
    final guide = PetCompanionGuide.build(
      profile: const PetProfile(),
      mastery: TextbookMastery([
        UnitMastery(
          unitId: 'unit-current',
          unitName: '当前单元',
          lessons: [_lesson(current, mastered: 0)],
        ),
        UnitMastery(
          unitId: 'unit-other',
          unitName: '后续单元',
          lessons: [_lesson(other, mastered: 0)],
        ),
      ]),
      catalog: PracticeCatalog([...current, ...other]),
      progress: const PracticeProgress({}),
    );

    final allowedIds = current.map((question) => question.id).toSet();
    expect(guide.goalSelection!.isAvailable, isTrue);
    expect(
      guide.goalSelection!.session!.attempts
          .map((attempt) => attempt.questionId)
          .every(allowedIds.contains),
      isTrue,
    );
    expect(
      guide.goalSelection!.session!.attempts.every(
        (attempt) =>
            attempt.direction == PracticeDirection.writeHanzi ||
            attempt.direction == PracticeDirection.writePinyin,
      ),
      isTrue,
    );
  });

  test('目标课文不足三个兼容尝试时返回不可用选择', () {
    const sparse = [
      PracticeQuestion(
        id: 'sparse-character',
        kind: '识字',
        category: '字',
        answerLines: ['春'],
        promptLines: ['chūn'],
        source: '测试',
        chapterId: 'lesson-sparse',
      ),
    ];
    final guide = PetCompanionGuide.build(
      profile: const PetProfile(),
      mastery: TextbookMastery([
        UnitMastery(
          unitId: 'unit-1',
          unitName: '第一单元',
          lessons: [_lesson(sparse, mastered: 0)],
        ),
      ]),
      catalog: PracticeCatalog(sparse),
      progress: const PracticeProgress({}),
    );

    expect(guide.goalSelection!.isAvailable, isFalse);
    expect(guide.goalSelection!.reason, contains('不足 3 题'));
  });

  test('主动邀请每天最多展示一次，接受后进入冷却期', () {
    final guide = PetCompanionGuide(
      goal: '继续学习',
      invitation: PetPracticeInvitation(
        action: QuickPracticeAction.mixedReview,
        session: QuickPracticeSession(
          action: QuickPracticeAction.mixedReview,
          attempts: [
            for (var index = 0; index < 3; index++)
              const QuickPracticeAttempt(
                questionId: 'question-0',
                direction: PracticeDirection.writeHanzi,
              ),
          ],
        ),
        message: '来练三题吧',
      ),
    );
    const key = 'grade2b';
    final now = DateTime(2026, 9, 18, 10);
    final available = PetInvitationScheduler.evaluate(
      guide: guide,
      events: const [],
      textbookKey: key,
      now: now,
    );
    expect(available.canPresent, isTrue);

    final presented = _event(
      id: 'present',
      type: EngagementEventType.invitationPresented,
      date: '2026-09-18',
      context: const EngagementEventContext(
        textbookKey: key,
        launchSource: EngagementLaunchSource.invitation,
      ),
    );
    expect(
      PetInvitationScheduler.evaluate(
        guide: guide,
        events: [presented],
        textbookKey: key,
        now: now,
      ).reason,
      'presented-today',
    );

    final accepted = _event(
      id: 'accepted',
      type: EngagementEventType.quickPracticeStarted,
      date: '2026-09-17',
      context: const EngagementEventContext(
        textbookKey: key,
        launchSource: EngagementLaunchSource.invitation,
      ),
    );
    expect(
      PetInvitationScheduler.evaluate(
        guide: guide,
        events: [accepted],
        textbookKey: key,
        now: now,
      ).reason,
      'accepted-cooldown',
    );
  });
}

List<PracticeQuestion> _questions(String chapterId, int count) => [
  for (var index = 0; index < count; index++)
    PracticeQuestion(
      id: '$chapterId-question-$index',
      kind: '词语',
      category: '词',
      answerLines: const ['春天'],
      promptLines: const ['chūn tiān'],
      source: '测试',
      chapterId: chapterId,
    ),
];

LessonMastery _lesson(
  List<PracticeQuestion> questions, {
  required int mastered,
}) => LessonMastery(
  chapterId: questions.first.chapterId,
  chapterName: questions.first.chapterId,
  questions: questions,
  masteredQuestionIds: questions
      .take(mastered)
      .map((question) => question.id)
      .toSet(),
);

EngagementEvent _event({
  required String id,
  required EngagementEventType type,
  required String date,
  required EngagementEventContext context,
}) => EngagementEvent(
  eventId: id,
  schemaVersion: 1,
  type: type,
  occurredAtUtc: DateTime.utc(2026, 9, 18),
  localDate: date,
  anonymousInstallId: 'install',
  sessionId: 'session',
  sequence: id.hashCode,
  context: context,
);
