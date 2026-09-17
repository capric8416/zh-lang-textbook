import 'practice.dart';

enum QuickPracticeAction { mixedReview, mistakeFirst, characters, readAloud }

class QuickPracticeAttempt {
  const QuickPracticeAttempt({
    required this.questionId,
    required this.direction,
  });

  final String questionId;
  final PracticeDirection direction;

  String get attemptId => '$questionId:${direction.name}';
}

class QuickPracticeSession {
  const QuickPracticeSession({required this.action, required this.attempts})
    : assert(attempts.length == 3);

  final QuickPracticeAction action;
  final List<QuickPracticeAttempt> attempts;
}

class QuickPracticeSelection {
  const QuickPracticeSelection.available(this.session) : reason = null;

  const QuickPracticeSelection.unavailable(this.reason) : session = null;

  final QuickPracticeSession? session;
  final String? reason;

  bool get isAvailable => session != null;
}
