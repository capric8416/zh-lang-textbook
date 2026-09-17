import 'package:flutter/material.dart';
import '../models/pet.dart';
import '../services/pet_growth.dart';
import '../widgets/pet_avatar.dart';

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
    if (store == null)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final profile = store.profile;
    return Scaffold(
      appBar: AppBar(title: const Text('宠物之家')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  PetAvatar(
                    size: 170,
                    appearance: PetAppearance.fromBreed(profile.breed),
                    decoration: petDecoration(profile.selectedDecoration),
                  ),
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
