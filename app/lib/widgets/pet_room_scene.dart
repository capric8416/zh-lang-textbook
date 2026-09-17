import 'package:flutter/material.dart';

import '../models/pet.dart';
import 'pet_avatar.dart';

class PetRoomScene extends StatelessWidget {
  const PetRoomScene({super.key, required this.profile});

  final PetProfile profile;

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
                  key: ValueKey('furniture-${item.id}'),
                  alignment: _alignment(item.slot),
                  child: _FurnitureTile(item: item),
                ),
              Align(
                alignment: const Alignment(0, 0.3),
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

class _FurnitureTile extends StatelessWidget {
  const _FurnitureTile({required this.item});

  final PetFurniture item;

  @override
  Widget build(BuildContext context) => Semantics(
    label: item.name,
    child: Container(
      width: 74,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_icon(item.id), size: 30),
          Text(
            item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ],
      ),
    ),
  );

  IconData _icon(String id) => switch (id) {
    'pet-bed' => Icons.bed_outlined,
    'soft-rug' => Icons.texture,
    'toy-box' => Icons.toys_outlined,
    'study-desk' => Icons.desk_outlined,
    'desk-lamp' => Icons.light_outlined,
    'bookcase' => Icons.shelves,
    'shade-tree' => Icons.park_outlined,
    'flower-pot' => Icons.local_florist_outlined,
    'garden-swing' => Icons.deck_outlined,
    _ => Icons.chair_outlined,
  };
}
