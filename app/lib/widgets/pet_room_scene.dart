import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/pet.dart';
import 'pet_avatar.dart';

class PetRoomScene extends StatelessWidget {
  const PetRoomScene({
    super.key,
    required this.profile,
    this.onFurnitureTap,
    this.actionDescription,
    this.onRevealShown,
    this.petAlignmentX = 0,
  });

  final PetProfile profile;
  final ValueChanged<PetFurniture>? onFurnitureTap;
  final String? Function(PetFurniture)? actionDescription;
  final ValueChanged<String>? onRevealShown;
  final double petAlignmentX;

  @override
  Widget build(BuildContext context) {
    final room = petRoom(profile.selectedRoom);
    final items = petFurniture
        .where(
          (item) =>
              item.roomId == room.id &&
              profile.unlockedFurniture.contains(item.id),
        )
        .toList();
    final palette = _palette(room.id);
    return Semantics(
      label: '${room.name}，已摆放${items.length}件家具',
      child: AspectRatio(
        aspectRatio: 1.55,
        child: Container(
          key: ValueKey('pet-room-${room.id}'),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [palette.$1, palette.$2],
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: 72,
                child: ColoredBox(color: palette.$3),
              ),
              for (final item in items)
                Align(
                  alignment: _alignment(item.slot),
                  child: _FurnitureTile(
                    key: ValueKey('furniture-${item.id}'),
                    item: item,
                    onTap: actionDescription?.call(item) == null
                        ? null
                        : () => onFurnitureTap?.call(item),
                    actionDescription: actionDescription?.call(item),
                    state: profile.furnitureState(item.id),
                    reveal: profile.pendingFurnitureReveals.contains(item.id),
                    onRevealShown: onRevealShown,
                  ),
                ),
              Align(
                alignment: Alignment(petAlignmentX, 0.3),
                child: PetAvatar(
                  size: 126,
                  appearance: PetAppearance.fromBreed(profile.breed),
                  decoration: petDecoration(profile.selectedDecoration),
                ),
              ),
              Positioned(
                left: 14,
                top: 12,
                child: Chip(
                  avatar: const Icon(Icons.home_outlined, size: 18),
                  label: Text(room.name),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  (Color, Color, Color) _palette(String roomId) => switch (roomId) {
    'study-room' => (
      const Color(0xfffff4d6),
      const Color(0xffffe1a8),
      const Color(0xffc89562),
    ),
    'yard' => (
      const Color(0xffcceeff),
      const Color(0xffe8f8e1),
      const Color(0xff8bcf7c),
    ),
    _ => (
      const Color(0xffffe8df),
      const Color(0xfffff5eb),
      const Color(0xffd8aa83),
    ),
  };

  Alignment _alignment(String slot) => switch (slot) {
    'left-wall' => const Alignment(-0.75, -0.45),
    'right-wall' => const Alignment(0.75, -0.45),
    'left-floor' => const Alignment(-0.72, 0.72),
    'right-floor' => const Alignment(0.72, 0.72),
    _ => const Alignment(0, 0.84),
  };
}

class _FurnitureTile extends StatefulWidget {
  const _FurnitureTile({
    super.key,
    required this.item,
    required this.onTap,
    required this.actionDescription,
    required this.state,
    required this.reveal,
    required this.onRevealShown,
  });

  final PetFurniture item;
  final VoidCallback? onTap;
  final String? actionDescription;
  final FurnitureVisualState state;
  final bool reveal;
  final ValueChanged<String>? onRevealShown;

  @override
  State<_FurnitureTile> createState() => _FurnitureTileState();
}

class _FurnitureTileState extends State<_FurnitureTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _started = false;
  bool _revealScheduled = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started && widget.onTap != null) {
      _started = true;
      if (!MediaQuery.disableAnimationsOf(context)) _controller.forward();
    }
    if (widget.reveal && !_revealScheduled) {
      _revealScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        if (!MediaQuery.disableAnimationsOf(context)) {
          await Future<void>.delayed(const Duration(milliseconds: 900));
        }
        if (mounted) widget.onRevealShown?.call(widget.item.id);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tile = Container(
      width: 74,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                _icon(widget.item.id, widget.state),
                key: widget.state == FurnitureVisualState.active
                    ? ValueKey('furniture-active-${widget.item.id}')
                    : null,
                size: 30,
                color: _activeColor(widget.item.id, widget.state),
              ),
              if (widget.onTap != null)
                const Positioned(
                  right: -12,
                  top: -9,
                  child: Icon(Icons.play_circle_fill, size: 16),
                ),
              if (widget.reveal)
                const Positioned(
                  left: -12,
                  top: -10,
                  child: Icon(Icons.auto_awesome, size: 16),
                ),
            ],
          ),
          Text(
            widget.item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    );
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final wave = math.sin(_controller.value * math.pi);
        return Transform.translate(
          offset: widget.item.id == 'bookcase'
              ? Offset(0, -4 * wave)
              : Offset.zero,
          child: Transform.rotate(
            angle: widget.item.id == 'flower-pot' || widget.item.id == 'toy-box'
                ? 0.06 * wave
                : 0,
            child: Transform.scale(
              scale: widget.item.id == 'desk-lamp' ? 1 + 0.1 * wave : 1,
              child: child,
            ),
          ),
        );
      },
      child: Semantics(
        button: widget.onTap != null,
        label: widget.actionDescription == null
            ? widget.item.name
            : '${widget.item.name}，${widget.actionDescription}',
        child: widget.onTap == null
            ? tile
            : Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: widget.onTap,
                  child: tile,
                ),
              ),
      ),
    );
  }

  IconData _icon(String id, FurnitureVisualState state) =>
      switch ((id, state)) {
        ('bookcase', FurnitureVisualState.active) => Icons.auto_stories,
        ('flower-pot', FurnitureVisualState.active) => Icons.local_florist,
        ('desk-lamp', FurnitureVisualState.active) => Icons.lightbulb,
        ('toy-box', FurnitureVisualState.active) => Icons.inventory_2,
        ('pet-bed', _) => Icons.bed_outlined,
        ('soft-rug', _) => Icons.texture,
        ('toy-box', _) => Icons.toys_outlined,
        ('study-desk', _) => Icons.desk_outlined,
        ('desk-lamp', _) => Icons.light_outlined,
        ('bookcase', _) => Icons.shelves,
        ('shade-tree', _) => Icons.park_outlined,
        ('flower-pot', _) => Icons.local_florist_outlined,
        ('garden-swing', _) => Icons.deck_outlined,
        _ => Icons.chair_outlined,
      };

  Color? _activeColor(String id, FurnitureVisualState state) {
    if (state != FurnitureVisualState.active) return null;
    return switch (id) {
      'desk-lamp' => const Color(0xffffb703),
      'flower-pot' => const Color(0xffe85d75),
      'bookcase' => const Color(0xff6d8f3d),
      'toy-box' => const Color(0xff3d9be9),
      _ => null,
    };
  }
}
