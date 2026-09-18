import '../models/engagement_event.dart';
import '../models/pet_learning_goal.dart';
import 'pet_companion.dart';

class PetInvitationSchedule {
  const PetInvitationSchedule({
    required this.invitation,
    required this.goal,
    required this.suppressed,
    required this.reason,
  });

  final PetPracticeInvitation? invitation;
  final PetLearningGoal? goal;
  final bool suppressed;
  final String reason;

  bool get canPresent => invitation != null && !suppressed;
}

class PetInvitationScheduler {
  const PetInvitationScheduler._();

  static const acceptanceCooldownDays = 2;

  static PetInvitationSchedule evaluate({
    required PetCompanionGuide guide,
    required Iterable<EngagementEvent> events,
    required String textbookKey,
    required DateTime now,
  }) {
    final invitation = guide.invitation;
    if (invitation == null) {
      return PetInvitationSchedule(
        invitation: null,
        goal: guide.learningGoal,
        suppressed: true,
        reason: 'no-useful-action',
      );
    }
    final date = EngagementEvent.localDateFor(now);
    final relevant = events.where(
      (event) =>
          event.context.textbookKey == textbookKey &&
          (event.type == EngagementEventType.invitationPresented ||
              event.type == EngagementEventType.invitationSkipped ||
              event.type == EngagementEventType.quickPracticeStarted),
    );
    final presentedToday = relevant.any(
      (event) =>
          event.type == EngagementEventType.invitationPresented &&
          event.localDate == date,
    );
    final skippedToday = relevant.any(
      (event) =>
          event.type == EngagementEventType.invitationSkipped &&
          event.localDate == date,
    );
    if (presentedToday || skippedToday) {
      return PetInvitationSchedule(
        invitation: invitation,
        goal: guide.learningGoal,
        suppressed: true,
        reason: presentedToday ? 'presented-today' : 'skipped-today',
      );
    }
    final accepted = relevant.where(
      (event) =>
          event.type == EngagementEventType.quickPracticeStarted &&
          event.context.launchSource == EngagementLaunchSource.invitation,
    );
    final current = DateTime.tryParse(date)!;
    final acceptedRecently = accepted.any((event) {
      final acceptedDate = DateTime.tryParse(event.localDate);
      return acceptedDate != null &&
          current.difference(acceptedDate).inDays >= 0 &&
          current.difference(acceptedDate).inDays < acceptanceCooldownDays;
    });
    if (acceptedRecently) {
      return PetInvitationSchedule(
        invitation: invitation,
        goal: guide.learningGoal,
        suppressed: true,
        reason: 'accepted-cooldown',
      );
    }
    return PetInvitationSchedule(
      invitation: invitation,
      goal: guide.learningGoal,
      suppressed: false,
      reason: 'available',
    );
  }
}
