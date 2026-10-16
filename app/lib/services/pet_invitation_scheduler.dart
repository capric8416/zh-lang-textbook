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

  static PetInvitationSchedule evaluate({required PetCompanionGuide guide}) {
    final invitation = guide.invitation;
    if (invitation == null) {
      return PetInvitationSchedule(
        invitation: null,
        goal: guide.learningGoal,
        suppressed: true,
        reason: 'no-useful-action',
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
