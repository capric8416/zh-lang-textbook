import '../models/practice.dart';
import '../models/quick_practice.dart';
import 'practice_progress.dart';

class QuickPracticeSelector {
  const QuickPracticeSelector._();

  static QuickPracticeSelection select({
    required PracticeCatalog catalog,
    required PracticeProgress progress,
    required QuickPracticeAction action,
    Set<String>? chapterIds,
    bool allowActionFallback = true,
    DateTime? now,
  }) {
    final selectionTime = now ?? DateTime.now();
    final candidates = <_Candidate>[
      for (final question in catalog.questions)
        if (chapterIds == null || chapterIds.contains(question.chapterId))
          for (final direction in PracticeDirection.values)
            if (question.supportsDirection(direction) &&
                progress
                    .forQuestion(question.attemptId(direction))
                    .isAvailableAt(selectionTime))
              _Candidate(
                question: question,
                direction: direction,
                progress: progress.forQuestion(question.attemptId(direction)),
              ),
    ];
    candidates.sort((left, right) => _compare(left, right, selectionTime));
    final preferred = candidates.where((item) => _preferred(item, action));
    final fallback = allowActionFallback
        ? candidates.where((item) => !_preferred(item, action))
        : const Iterable<_Candidate>.empty();
    final selected = <_Candidate>[...preferred, ...fallback].take(3).toList();
    if (selected.length < 3) {
      return const QuickPracticeSelection.unavailable(
        '当前范围可练习不足 3 题，部分题目可能正在等待间隔巩固',
      );
    }
    return QuickPracticeSelection.available(
      QuickPracticeSession(
        action: action,
        attempts: [
          for (final item in selected)
            QuickPracticeAttempt(
              questionId: item.question.id,
              direction: item.direction,
            ),
        ],
      ),
    );
  }

  static bool _preferred(_Candidate item, QuickPracticeAction action) =>
      switch (action) {
        QuickPracticeAction.mixedReview => true,
        QuickPracticeAction.mistakeFirst => item.progress.isWrong,
        QuickPracticeAction.characters =>
          item.direction == PracticeDirection.writeHanzi ||
              item.direction == PracticeDirection.writePinyin,
        QuickPracticeAction.readAloud =>
          item.direction == PracticeDirection.readAloud &&
              item.question.category != '字',
      };

  static int _compare(_Candidate left, _Candidate right, DateTime now) {
    final priority = right.progress
        .selectionWeight(now)
        .compareTo(left.progress.selectionWeight(now));
    if (priority != 0) return priority;
    final attempts = left.progress.totalCount.compareTo(
      right.progress.totalCount,
    );
    if (attempts != 0) return attempts;
    final question = left.question.id.compareTo(right.question.id);
    if (question != 0) return question;
    return left.direction.index.compareTo(right.direction.index);
  }
}

class _Candidate {
  const _Candidate({
    required this.question,
    required this.direction,
    required this.progress,
  });

  final PracticeQuestion question;
  final PracticeDirection direction;
  final QuestionProgress progress;
}

QuickPracticeAction? quickPracticeActionForFurniture(String furnitureId) =>
    switch (furnitureId) {
      'bookcase' => QuickPracticeAction.mixedReview,
      'toy-box' => QuickPracticeAction.mistakeFirst,
      'desk-lamp' => QuickPracticeAction.characters,
      'flower-pot' => QuickPracticeAction.readAloud,
      _ => null,
    };

String quickPracticeActionLabel(QuickPracticeAction action) => switch (action) {
  QuickPracticeAction.mixedReview => '三题综合复习',
  QuickPracticeAction.mistakeFirst => '三题错题优先',
  QuickPracticeAction.characters => '三题汉字拼音',
  QuickPracticeAction.readAloud => '三题朗读检查',
};
