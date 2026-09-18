import 'package:flutter/material.dart';

import '../models/pet.dart';
import '../models/pet_learning_goal.dart';
import '../services/learning_mastery.dart';
import 'pet_avatar.dart';

class PetGrowthCard extends StatelessWidget {
  const PetGrowthCard({
    super.key,
    required this.profile,
    required this.mastery,
    this.goal,
    this.greeting,
    this.invitation,
    this.onAcceptInvitation,
    this.onSkipInvitation,
    this.learningGoal,
    this.goalActionLabel,
    this.onOpenGoal,
    this.onOpenHome,
  });

  final PetProfile profile;
  final TextbookMastery mastery;
  final String? goal;
  final String? greeting;
  final String? invitation;
  final VoidCallback? onAcceptInvitation;
  final VoidCallback? onSkipInvitation;
  final PetLearningGoal? learningGoal;
  final String? goalActionLabel;
  final VoidCallback? onOpenGoal;
  final VoidCallback? onOpenHome;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final lesson = mastery.nextIncompleteLesson;
    final progress = lesson == null ? 1.0 : lesson.percentage / 100;
    return Card(
      key: const ValueKey('pet-growth-card'),
      elevation: 0,
      color: colors.tertiaryContainer.withValues(alpha: 0.55),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            PetAvatar(
              size: 88,
              appearance: PetAppearance.fromBreed(profile.breed),
              decoration: petDecoration(profile.selectedDecoration),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${profile.name} · ${petBreed(profile.breed).name}',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      IconButton(
                        onPressed: onOpenHome,
                        tooltip: '打开宠物之家',
                        icon: const Icon(Icons.home_outlined),
                      ),
                      Text(
                        '大阶段 ${profile.majorStage}',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '成长值 ${profile.growthPoints}',
                    style: TextStyle(
                      color: colors.onTertiaryContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (greeting != null) ...[
                    const SizedBox(height: 6),
                    Text(greeting!, key: const ValueKey('pet-daily-greeting')),
                  ],
                  const SizedBox(height: 10),
                  Text(
                    lesson == null
                        ? '本册学习阶段已全部完成！'
                        : '${lesson.chapterName}  ${lesson.masteredCount}/${lesson.totalCount}（${lesson.percentage}%）',
                  ),
                  const SizedBox(height: 7),
                  LinearProgressIndicator(
                    value: progress.clamp(0, 1),
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  if (goal != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        const Icon(Icons.lock_open_outlined, size: 18),
                        const SizedBox(width: 6),
                        Expanded(child: Text(goal!)),
                      ],
                    ),
                  ],
                  if (learningGoal != null) ...[
                    const SizedBox(height: 12),
                    Card(
                      key: const ValueKey('pet-learning-goal'),
                      margin: EdgeInsets.zero,
                      color: colors.surface.withValues(alpha: 0.7),
                      child: InkWell(
                        onTap: onOpenGoal,
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Icon(
                                learningGoal!.isComplete
                                    ? Icons.check_circle_outline
                                    : Icons.flag_outlined,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      learningGoal!.isComplete
                                          ? '目标完成：${learningGoal!.unitName}'
                                          : '下一步：${goalActionLabel ?? learningGoal!.actionLabel}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      learningGoal!.isComplete
                                          ? learningGoal!.outcome
                                          : '${learningGoal!.unitName}  ${learningGoal!.progressLabel}，还差 ${learningGoal!.remaining} 个小目标',
                                    ),
                                    const SizedBox(height: 6),
                                    LinearProgressIndicator(
                                      value: learningGoal!.progress,
                                      minHeight: 5,
                                      borderRadius: BorderRadius.circular(99),
                                    ),
                                  ],
                                ),
                              ),
                              if (onOpenGoal != null)
                                const Icon(Icons.arrow_forward_ios, size: 15),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (invitation != null) ...[
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      key: const ValueKey('pet-practice-invitation'),
                      onPressed: onAcceptInvitation,
                      icon: const Icon(Icons.pets_outlined),
                      label: Text(invitation!),
                    ),
                    if (onSkipInvitation != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: onSkipInvitation,
                          child: const Text('稍后再说'),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
