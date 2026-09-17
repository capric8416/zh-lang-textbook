import 'package:flutter/material.dart';
import '../models/pet.dart';
import '../services/pet_growth.dart';
import '../widgets/pet_room_scene.dart';

class PetHomePage extends StatefulWidget {
  const PetHomePage({super.key});
  @override
  State<PetHomePage> createState() => _PetHomePageState();
}

class _PetHomePageState extends State<PetHomePage> {
  PetGrowthStore? _store;
  String _message = '选一个喜欢的伙伴吧';
  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    final store = await PetGrowthStore.open();
    if (mounted) setState(() => _store = store);
  }

  Future<void> _interact(String text) async {
    setState(() => _message = text);
  }

  @override
  Widget build(BuildContext context) {
    final store = _store;
    if (store == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final profile = store.profile;
    return Scaffold(
      appBar: AppBar(title: const Text('宠物之家')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('选择房间', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final room in petRooms)
                ChoiceChip(
                  key: ValueKey('room-${room.id}'),
                  avatar: const Icon(Icons.home_outlined, size: 18),
                  label: Text(room.name),
                  selected: profile.selectedRoom == room.id,
                  onSelected: (_) async {
                    await store.selectRoom(room.id);
                    if (mounted) setState(() {});
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          PetRoomScene(profile: profile),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(
                    _message,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    '成长值 ${profile.growthPoints} · 大阶段 ${profile.majorStage}',
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton.tonal(
                        onPressed: () => _interact('摸摸头，真棒！'),
                        child: const Text('摸摸头'),
                      ),
                      FilledButton.tonal(
                        onPressed: () => _interact('你好呀！'),
                        child: const Text('打个招呼'),
                      ),
                      FilledButton.tonal(
                        onPressed: () => _interact('尾巴摇起来啦！'),
                        child: const Text('摇尾巴'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('房间家具', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in petFurniture.where(
                (item) => item.roomId == profile.selectedRoom,
              ))
                Chip(
                  key: ValueKey('furniture-status-${item.id}'),
                  avatar: Icon(
                    profile.unlockedFurniture.contains(item.id)
                        ? Icons.check_circle_outline
                        : Icons.lock_outline,
                    size: 18,
                  ),
                  label: Text(
                    profile.unlockedFurniture.contains(item.id)
                        ? item.name
                        : '${item.name}（大阶段${item.unlockStage}解锁）',
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text('选择伙伴', style: Theme.of(context).textTheme.titleLarge),
          Wrap(
            spacing: 8,
            children: [
              for (final breed in petBreeds)
                ChoiceChip(
                  label: Text(
                    profile.unlockedBreeds.contains(breed.id)
                        ? breed.name
                        : '${breed.name}（大阶段${breed.unlockStage}解锁）',
                  ),
                  selected: profile.breed == breed.id,
                  onSelected: profile.unlockedBreeds.contains(breed.id)
                      ? (_) async {
                          await store.selectBreed(breed.id);
                          setState(() {});
                        }
                      : null,
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text('学习装饰', style: Theme.of(context).textTheme.titleLarge),
          Wrap(
            spacing: 8,
            children: [
              for (final decoration in petDecorations)
                ChoiceChip(
                  label: Text(
                    profile.unlockedDecorations.contains(decoration.id)
                        ? decoration.name
                        : '${decoration.name}（大阶段${decoration.unlockStage}解锁）',
                  ),
                  selected: profile.selectedDecoration == decoration.id,
                  onSelected:
                      profile.unlockedDecorations.contains(decoration.id)
                      ? (_) async {
                          await store.selectDecoration(decoration.id);
                          setState(() {});
                        }
                      : null,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
