import 'package:flutter/material.dart';

import '../models/pet.dart';
import '../models/pet_mission.dart';
import 'pet_avatar.dart';

enum PetPracticeMood { idle, thinking, celebrate, encourage }

class PetPracticeCompanion extends StatelessWidget {
  const PetPracticeCompanion({
    super.key,
    required this.profile,
    required this.mission,
    required this.mood,
    required this.completedSteps,
  });

  final PetProfile profile;
  final PetCompanionMission mission;
  final PetPracticeMood mood;
  final int completedSteps;

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final message = switch (mood) {
      PetPracticeMood.thinking => '${profile.name}陪你慢慢想，不着急。',
      PetPracticeMood.celebrate => '答对啦，${profile.name}开心地摇摇尾巴！',
      PetPracticeMood.encourage => '${profile.name}陪你继续试，完成也有进步。',
      PetPracticeMood.idle when completedSteps > 0 =>
        mission.steps[(completedSteps - 1).clamp(0, 2)],
      PetPracticeMood.idle => mission.intro,
    };
    final expression = switch (mood) {
      PetPracticeMood.celebrate => PetExpression.wink,
      PetPracticeMood.thinking => PetExpression.happy,
      PetPracticeMood.encourage => PetExpression.happy,
      PetPracticeMood.idle => PetExpression.happy,
    };
    return Card(
      key: const ValueKey('pet-practice-companion'),
      color: Theme.of(context).colorScheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            AnimatedScale(
              duration: reducedMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              scale: mood == PetPracticeMood.celebrate ? 1.08 : 1,
              child: PetAvatar(
                size: 62,
                expression: expression,
                appearance: PetAppearance.fromBreed(profile.breed),
                decoration: petDecoration(profile.selectedDecoration),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mission.title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: reducedMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                    child: Text(
                      message,
                      key: ValueKey('$mood-$completedSteps'),
                    ),
                  ),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                    key: const ValueKey('pet-mission-progress'),
                    value: completedSteps / 3,
                    minHeight: 6,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PetMissionCompletionDialog extends StatelessWidget {
  const PetMissionCompletionDialog({
    super.key,
    required this.petName,
    required this.mission,
  });

  final String petName;
  final PetCompanionMission mission;

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const ValueKey('pet-mission-complete'),
    title: Text(mission.completion),
    content: Text('$petName想问：还要再轻松练三题吗？'),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('先回去看看'),
      ),
      FilledButton(
        key: const ValueKey('repeat-quick-practice'),
        onPressed: () => Navigator.pop(context, true),
        child: const Text('再练三题'),
      ),
    ],
  );
}
