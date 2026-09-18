import 'practice.dart';
import 'quick_practice.dart';
import '../services/learning_mastery.dart';
import '../services/practice_progress.dart';

enum PetLearningGoalKind { unitMastery, vocabularyMastery, quickPractice }

class PetLearningGoal {
  const PetLearningGoal({
    required this.id,
    required this.kind,
    required this.unitId,
    required this.unitName,
    required this.chapterIds,
    required this.current,
    required this.target,
    required this.action,
    required this.actionLabel,
    required this.outcome,
  });

  final String id;
  final PetLearningGoalKind kind;
  final String unitId;
  final String unitName;
  final List<String> chapterIds;
  final int current;
  final int target;
  final QuickPracticeAction action;
  final String actionLabel;
  final String outcome;

  bool get isComplete => target > 0 && current >= target;
  int get remaining => (target - current).clamp(0, target);
  double get progress => target == 0 ? 0 : (current / target).clamp(0, 1);

  String get progressLabel => '$current/$target';
}

class PetLearningGoalProjector {
  const PetLearningGoalProjector._();

  static PetLearningGoal? primary({
    required TextbookMastery mastery,
    required PracticeCatalog catalog,
    required PracticeProgress progress,
  }) {
    final goals = buildAll(
      mastery: mastery,
      catalog: catalog,
      progress: progress,
    );
    return goals.firstOrNull;
  }

  static List<PetLearningGoal> buildAll({
    required TextbookMastery mastery,
    required PracticeCatalog catalog,
    required PracticeProgress progress,
  }) {
    final unit = mastery.units
        .where(
          (candidate) =>
              candidate.eligibleLessons.isNotEmpty && !candidate.isComplete,
        )
        .firstOrNull;
    if (unit == null) return const [];
    final goals = <PetLearningGoal>[];
    for (final lesson in unit.eligibleLessons.where(
      (candidate) => !candidate.isPassed,
    )) {
      final target = (lesson.totalCount * 60 + 99) ~/ 100;
      final wordQuestions = lesson.questions
          .where((question) => question.category == '词')
          .toList(growable: false);
      final useWordAction = wordQuestions.length >= 3;
      goals.add(
        PetLearningGoal(
          id: 'unit:${unit.unitId}:lesson:${lesson.chapterId}',
          kind: useWordAction
              ? PetLearningGoalKind.vocabularyMastery
              : PetLearningGoalKind.unitMastery,
          unitId: unit.unitId,
          unitName: '${unit.unitName} · ${lesson.chapterName}',
          chapterIds: [lesson.chapterId],
          current: lesson.masteredCount,
          target: target,
          action: useWordAction
              ? QuickPracticeAction.characters
              : QuickPracticeAction.mixedReview,
          actionLabel: useWordAction ? '练三题巩固词语' : '练三题推进本课',
          outcome: useWordAction ? '完成后，小台灯会亮得更暖' : '完成后，小书柜会再添一本书',
        ),
      );
    }
    goals.sort((left, right) {
      final completion = left.isComplete == right.isComplete
          ? 0
          : left.isComplete
          ? 1
          : -1;
      if (completion != 0) return completion;
      final remaining = left.remaining.compareTo(right.remaining);
      return remaining != 0 ? remaining : left.id.compareTo(right.id);
    });
    return goals;
  }
}
