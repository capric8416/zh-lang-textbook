import '../models/pet.dart';
import '../models/practice.dart';
import '../models/quick_practice.dart';
import 'learning_mastery.dart';
import 'practice_progress.dart';
import 'quick_practice.dart';

class PetCompanionGuide {
  const PetCompanionGuide({required this.goal, this.invitation});

  final String goal;
  final PetPracticeInvitation? invitation;

  static PetCompanionGuide build({
    required PetProfile profile,
    required TextbookMastery mastery,
    required PracticeCatalog catalog,
    required PracticeProgress progress,
  }) {
    final unlock = _nextUnlock(profile);
    final unit = mastery.units
        .where(
          (candidate) =>
              candidate.eligibleLessons.isNotEmpty && !candidate.isComplete,
        )
        .firstOrNull;
    final remaining = unit?.eligibleLessons.fold<int>(0, (total, lesson) {
      final passCount = (lesson.totalCount * 60 + 99) ~/ 100;
      return total + (passCount - lesson.masteredCount).clamp(0, passCount);
    });
    final goal = switch ((unlock, unit, remaining)) {
      (null, _, _) => '${profile.name}已经收集完所有伙伴装扮啦！',
      (_, null, _) => '完成下一个单元，${unlock!.name}就在前面等着${profile.name}！',
      (_, _, _) when unlock!.stage == profile.majorStage + 1 =>
        '再掌握 $remaining 道题，完成${unit!.unitName}，${unlock.name}就会解锁！',
      (_, _, _) => '继续完成单元，向${unlock.name}前进！',
    };
    return PetCompanionGuide(
      goal: goal,
      invitation: _invitation(profile, catalog, progress),
    );
  }

  static PetPracticeInvitation? _invitation(
    PetProfile profile,
    PracticeCatalog catalog,
    PracticeProgress progress,
  ) {
    final wrongCount = progress.wrongCountFor(catalog.questions);
    final actions = wrongCount > 0
        ? const [QuickPracticeAction.mistakeFirst]
        : const [
            QuickPracticeAction.mixedReview,
            QuickPracticeAction.characters,
            QuickPracticeAction.readAloud,
          ];
    final offset = wrongCount > 0
        ? 0
        : progress.completedCount % actions.length;
    for (var index = 0; index < actions.length; index++) {
      final action = actions[(offset + index) % actions.length];
      final selection = QuickPracticeSelector.select(
        catalog: catalog,
        progress: progress,
        action: action,
      );
      final session = selection.session;
      if (session == null) continue;
      return PetPracticeInvitation(
        action: action,
        session: session,
        message: _invitationMessage(profile.name, action),
      );
    }
    return null;
  }

  static String _invitationMessage(String name, QuickPracticeAction action) =>
      switch (action) {
        QuickPracticeAction.mistakeFirst => '$name想和你一起整理三个错题',
        QuickPracticeAction.mixedReview => '$name想陪你轻松练三题',
        QuickPracticeAction.characters => '$name想和你写三个汉字拼音',
        QuickPracticeAction.readAloud => '$name想听你朗读三题',
      };

  static _PetUnlock? _nextUnlock(PetProfile profile) {
    final candidates =
        <_PetUnlock>[
          for (final item in petFurniture)
            if (!profile.unlockedFurniture.contains(item.id))
              _PetUnlock(
                item.name,
                item.unlockStage,
                quickPracticeActionForFurniture(item.id) != null ? 0 : 2,
              ),
          for (final breed in petBreeds)
            if (!profile.unlockedBreeds.contains(breed.id))
              _PetUnlock(breed.name, breed.unlockStage, 1),
          for (final decoration in petDecorations)
            if (!profile.unlockedDecorations.contains(decoration.id))
              _PetUnlock(decoration.name, decoration.unlockStage, 3),
        ]..sort((a, b) {
          final stage = a.stage.compareTo(b.stage);
          return stage != 0 ? stage : a.kind.compareTo(b.kind);
        });
    return candidates.firstOrNull;
  }
}

class PetPracticeInvitation {
  const PetPracticeInvitation({
    required this.action,
    required this.session,
    required this.message,
  });

  final QuickPracticeAction action;
  final QuickPracticeSession session;
  final String message;
}

enum PetQuickReaction { tailWag, flowerGift, studyTogether }

PetQuickReaction petQuickReaction(QuickPracticeAction action) =>
    switch (action) {
      QuickPracticeAction.mistakeFirst => PetQuickReaction.studyTogether,
      QuickPracticeAction.mixedReview => PetQuickReaction.tailWag,
      QuickPracticeAction.characters => PetQuickReaction.studyTogether,
      QuickPracticeAction.readAloud => PetQuickReaction.flowerGift,
    };

class _PetUnlock {
  const _PetUnlock(this.name, this.stage, this.kind);

  final String name;
  final int stage;
  final int kind;
}
