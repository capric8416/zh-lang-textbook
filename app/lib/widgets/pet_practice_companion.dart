import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/pet.dart';
import '../models/pet_mission.dart';
import 'pet_avatar.dart';

enum PetPracticeMood { idle, thinking, celebrate, encourage }

enum PetActionKind { invite, think, correct, incorrect, complete, repeat }

class PetPracticeCompanion extends StatelessWidget {
  const PetPracticeCompanion({
    super.key,
    required this.profile,
    required this.mission,
    required this.mood,
    required this.completedSteps,
    this.action,
  });

  final PetProfile profile;
  final PetCompanionMission mission;
  final PetPracticeMood mood;
  final int completedSteps;
  final PetActionKind? action;

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
    final actionLabel = switch (action) {
      PetActionKind.invite => '挥挥爪子邀请你',
      PetActionKind.think => '安静陪你思考',
      PetActionKind.correct => '开心地摇尾巴',
      PetActionKind.incorrect => '拍拍爪子继续加油',
      PetActionKind.complete => '叼来一朵小花',
      PetActionKind.repeat => '在书桌旁等你',
      null => null,
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
              child: _PetActionAnimation(
                action: action,
                reducedMotion: reducedMotion,
                child: PetAvatar(
                  size: 62,
                  expression: expression,
                  appearance: PetAppearance.fromBreed(profile.breed),
                  decoration: petDecoration(profile.selectedDecoration),
                ),
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
                  if (actionLabel != null)
                    Text(
                      actionLabel,
                      key: const ValueKey('pet-action-label'),
                      style: Theme.of(context).textTheme.labelSmall,
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

class _PetActionAnimation extends StatefulWidget {
  const _PetActionAnimation({
    required this.action,
    required this.reducedMotion,
    required this.child,
  });

  final PetActionKind? action;
  final bool reducedMotion;
  final Widget child;

  @override
  State<_PetActionAnimation> createState() => _PetActionAnimationState();
}

class _PetActionAnimationState extends State<_PetActionAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 760),
    );
    _play();
  }

  @override
  void didUpdateWidget(covariant _PetActionAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.action != widget.action ||
        oldWidget.reducedMotion != widget.reducedMotion) {
      _play();
    }
  }

  void _play() {
    _controller
      ..stop()
      ..reset();
    if (!widget.reducedMotion && widget.action != null) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    child: widget.child,
    builder: (context, child) {
      final phase = Curves.easeOutBack.transform(_controller.value);
      final wave = Curves.easeInOut.transform(_controller.value);
      final (dx, dy, angle, scale) = switch (widget.action) {
        PetActionKind.invite => (
          0.0,
          -3 * wave,
          0.08 * math.sin(wave * math.pi * 2),
          1.0,
        ),
        PetActionKind.think => (0.0, -5 * math.sin(wave * math.pi), 0.0, 1.0),
        PetActionKind.correct => (
          0.0,
          -10 * math.sin(wave * math.pi),
          0.0,
          1 + 0.08 * phase,
        ),
        PetActionKind.incorrect => (
          4 * math.sin(wave * math.pi * 3),
          0.0,
          0.04 * math.sin(wave * math.pi * 3),
          1.0,
        ),
        PetActionKind.complete => (
          0.0,
          -7 * math.sin(wave * math.pi),
          0.0,
          1 + 0.05 * phase,
        ),
        PetActionKind.repeat => (0.0, -3 * wave, 0.0, 1.0),
        null => (0.0, 0.0, 0.0, 1.0),
      };
      return KeyedSubtree(
        key: ValueKey('pet-action-${widget.action?.name ?? 'idle'}'),
        child: Transform.translate(
          offset: Offset(dx, dy),
          child: Transform.rotate(
            angle: angle,
            child: Transform.scale(scale: scale, child: child),
          ),
        ),
      );
    },
  );
}

class PetMissionCompletionDialog extends StatefulWidget {
  const PetMissionCompletionDialog({
    super.key,
    required this.profile,
    required this.mission,
  });

  final PetProfile profile;
  final PetCompanionMission mission;

  @override
  State<PetMissionCompletionDialog> createState() =>
      _PetMissionCompletionDialogState();
}

class _PetMissionCompletionDialogState
    extends State<PetMissionCompletionDialog> {
  PetActionKind _action = PetActionKind.complete;

  @override
  Widget build(BuildContext context) => AlertDialog(
    key: const ValueKey('pet-mission-complete'),
    title: Text(widget.mission.completion),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PetActionAnimation(
          action: _action,
          reducedMotion: MediaQuery.disableAnimationsOf(context),
          child: PetAvatar(
            size: 72,
            expression: PetExpression.wink,
            appearance: PetAppearance.fromBreed(widget.profile.breed),
            decoration: petDecoration(widget.profile.selectedDecoration),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _action == PetActionKind.repeat
              ? '${widget.profile.name}已经在书桌旁等你啦！'
              : '${widget.profile.name}叼来一朵小花，还要再轻松练三题吗？',
        ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('先回去看看'),
      ),
      FilledButton(
        key: const ValueKey('repeat-quick-practice'),
        onPressed: () async {
          setState(() => _action = PetActionKind.repeat);
          if (!MediaQuery.disableAnimationsOf(context)) {
            await Future<void>.delayed(const Duration(milliseconds: 320));
          }
          if (context.mounted) Navigator.pop(context, true);
        },
        child: const Text('再练三题'),
      ),
    ],
  );
}
