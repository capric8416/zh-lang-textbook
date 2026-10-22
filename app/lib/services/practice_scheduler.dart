import 'dart:math';

import '../models/practice.dart';
import 'practice_progress.dart';

class PracticeScheduler {
  const PracticeScheduler._();

  static ({PracticeQuestion question, PracticeDirection direction})? select({
    required List<PracticeQuestion> questions,
    required PracticeProgress progress,
    required bool mistakesOnly,
    required DateTime now,
    required Random random,
    String? previousAttemptId,
  }) {
    final candidates =
        [
          for (final question in questions)
            for (final direction in PracticeDirection.values)
              if (question.supportsDirection(direction))
                (question: question, direction: direction),
        ].where((item) {
          final record = progress.forQuestion(
            item.question.attemptId(item.direction),
          );
          return record.isAvailableAt(now) && (!mistakesOnly || record.isWrong);
        }).toList();
    if (candidates.length > 1) {
      candidates.removeWhere(
        (item) => item.question.attemptId(item.direction) == previousAttemptId,
      );
    }
    if (candidates.isEmpty) return null;
    final weights = [
      for (final item in candidates)
        progress
            .forQuestion(item.question.attemptId(item.direction))
            .selectionWeight(now),
    ];
    var cursor = random.nextDouble() * weights.fold<double>(0, (a, b) => a + b);
    for (var index = 0; index < candidates.length; index++) {
      cursor -= weights[index];
      if (cursor <= 0) return candidates[index];
    }
    return candidates.last;
  }
}
