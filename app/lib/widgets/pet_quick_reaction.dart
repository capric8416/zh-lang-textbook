import 'dart:async';

import 'package:flutter/material.dart';

import '../models/pet.dart';
import '../models/quick_practice.dart';
import '../services/pet_companion.dart';
import 'pet_avatar.dart';

void showPetQuickReaction(
  BuildContext context, {
  required PetProfile profile,
  required QuickPracticeAction action,
}) {
  final overlay = Overlay.of(context);
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _PetQuickReactionOverlay(
      profile: profile,
      reaction: petQuickReaction(action),
      onDone: () => entry.remove(),
    ),
  );
  overlay.insert(entry);
}

class _PetQuickReactionOverlay extends StatefulWidget {
  const _PetQuickReactionOverlay({
    required this.profile,
    required this.reaction,
    required this.onDone,
  });

  final PetProfile profile;
  final PetQuickReaction reaction;
  final VoidCallback onDone;

  @override
  State<_PetQuickReactionOverlay> createState() =>
      _PetQuickReactionOverlayState();
}

class _PetQuickReactionOverlayState extends State<_PetQuickReactionOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    )..forward();
    _timer = Timer(const Duration(milliseconds: 1700), widget.onDone);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final message = switch (widget.reaction) {
      PetQuickReaction.tailWag => '${widget.profile.name}开心地摇起尾巴！',
      PetQuickReaction.flowerGift => '${widget.profile.name}叼来一朵小花送给你！',
      PetQuickReaction.studyTogether => '${widget.profile.name}趴在书桌旁陪着你！',
    };
    return IgnorePointer(
      child: SafeArea(
        child: Align(
          alignment: Alignment.bottomRight,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final value = reduceMotion
                  ? 1.0
                  : Curves.elasticOut.transform(_controller.value);
              return Transform.scale(
                scale: value,
                alignment: Alignment.bottomRight,
                child: child,
              );
            },
            child: Card(
              key: const ValueKey('pet-quick-reaction'),
              margin: const EdgeInsets.all(20),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 18, 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PetAvatar(
                      size: 72,
                      expression: PetExpression.wink,
                      appearance: PetAppearance.fromBreed(widget.profile.breed),
                      decoration: petDecoration(
                        widget.profile.selectedDecoration,
                      ),
                    ),
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: Text(
                        message,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
