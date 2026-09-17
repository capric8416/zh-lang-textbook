import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/pet.dart';
import 'pet_avatar.dart';

Future<void> showPetCelebrations(
  BuildContext context,
  List<PetCelebration> celebrations,
) async {
  for (final celebration in celebrations) {
    if (!context.mounted) return;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: '宠物成长庆祝',
      barrierColor: celebration.type == PetCelebrationType.unit
          ? Colors.black38
          : Colors.transparent,
      transitionDuration: Duration.zero,
      pageBuilder: (context, _, _) => _PetCelebrationOverlay(
        celebration: celebration,
        reduceMotion: MediaQuery.disableAnimationsOf(context),
      ),
    );
  }
}

class _PetCelebrationOverlay extends StatefulWidget {
  const _PetCelebrationOverlay({
    required this.celebration,
    required this.reduceMotion,
  });

  final PetCelebration celebration;
  final bool reduceMotion;

  @override
  State<_PetCelebrationOverlay> createState() => _PetCelebrationOverlayState();
}

class _PetCelebrationOverlayState extends State<_PetCelebrationOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(
          vsync: this,
          duration: Duration(
            milliseconds: widget.reduceMotion
                ? 700
                : widget.celebration.type == PetCelebrationType.unit
                ? 2600
                : 2100,
          ),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed && mounted) {
            Navigator.of(context).pop();
          }
        });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.celebration.type == PetCelebrationType.unit
      ? _buildUnit()
      : _buildLesson();

  Widget _buildLesson() {
    final celebration = widget.celebration;
    final expression = celebration.expression;
    return Material(
      key: const ValueKey('pet-lesson-celebration'),
      type: MaterialType.transparency,
      child: SafeArea(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final value = _controller.value;
            final horizontal = widget.reduceMotion
                ? 0.0
                : value < 0.3
                ? 180 * (1 - value / 0.3)
                : value > 0.82
                ? 180 * ((value - 0.82) / 0.18)
                : 0.0;
            final bounce = widget.reduceMotion
                ? 0.0
                : math.sin(value * math.pi * 10).abs() * -7;
            return Stack(
              children: [
                Positioned(
                  right: 18 - horizontal,
                  bottom: 22 + bounce,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: const [
                        BoxShadow(blurRadius: 18, color: Colors.black26),
                      ],
                      border: Border.all(
                        color: petAuraColor(expression),
                        width: 3,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 18, 12),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          PetAvatar(size: 88, expression: expression),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${celebration.threshold}% 达成！',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              Text(celebration.title ?? ''),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildUnit() => Material(
    key: const ValueKey('pet-unit-celebration'),
    color: Colors.transparent,
    child: AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Stack(
        fit: StackFit.expand,
        children: [
          if (!widget.reduceMotion)
            CustomPaint(painter: _ConfettiPainter(_controller.value)),
          Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 360),
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(32),
                boxShadow: const [
                  BoxShadow(blurRadius: 30, color: Colors.black38),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const PetAvatar(size: 150, expression: PetExpression.radiant),
                  const SizedBox(height: 16),
                  Text(
                    '单元大阶段通关！',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(widget.celebration.unitName ?? ''),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ConfettiPainter extends CustomPainter {
  const _ConfettiPainter(this.progress);

  final double progress;

  static const colors = [
    Color(0xffff5d73),
    Color(0xffffc857),
    Color(0xff4ecdc4),
    Color(0xff6c63ff),
    Color(0xffff8c42),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    for (var index = 0; index < 72; index++) {
      final seed = index * 37.0;
      final x = ((seed * 17) % 101) / 100 * size.width;
      final delay = (index % 9) / 15;
      final local = ((progress - delay).clamp(0.0, 1.0) / (1 - delay));
      final y = -20 + local * (size.height + 50);
      final sway = math.sin(progress * math.pi * 5 + seed) * 24;
      canvas.save();
      canvas.translate(x + sway, y);
      canvas.rotate(progress * 8 + index);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: 8, height: 15),
          const Radius.circular(2),
        ),
        Paint()..color = colors[index % colors.length],
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter oldDelegate) =>
      progress != oldDelegate.progress;
}
