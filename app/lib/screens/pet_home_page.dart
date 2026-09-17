import 'package:flutter/material.dart';
import '../models/pet.dart';
import '../models/practice.dart';
import '../models/textbook.dart';
import '../services/pet_growth.dart';
import '../services/practice_progress.dart';
import '../services/quick_practice.dart';
import '../services/textbook_repository.dart';
import '../widgets/pet_room_scene.dart';
import 'practice_page.dart';

class PetHomePage extends StatefulWidget {
  const PetHomePage({super.key, this.selection, this.textbook});

  final TextbookSelection? selection;
  final Textbook? textbook;

  @override
  State<PetHomePage> createState() => _PetHomePageState();
}

class _PetHomePageState extends State<PetHomePage> {
  PetGrowthStore? _store;
  PracticeProgressStore? _progressStore;
  PracticeCatalog? _catalog;
  String _message = '选一个喜欢的伙伴吧';
  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    final store = await PetGrowthStore.open();
    final selection = widget.selection;
    final textbook = widget.textbook;
    final progressStore = selection == null
        ? null
        : await PracticeProgressStore.open(selection.fileName);
    final catalog = textbook == null
        ? null
        : PracticeCatalog.fromTextbook(textbook);
    if (!mounted) return;
    setState(() {
      _store = store;
      _progressStore = progressStore;
      _catalog = catalog;
    });
  }

  Future<void> _interact(String text) async {
    setState(() => _message = text);
  }

  Future<void> _activateFurniture(PetFurniture furniture) async {
    final selection = widget.selection;
    final textbook = widget.textbook;
    if (selection == null || textbook == null) {
      _showUnavailable('请从教材学习页进入宠物之家');
      return;
    }
    if (furniture.id == 'study-desk') {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) =>
              PracticePage(selection: selection, textbook: textbook),
        ),
      );
      await _refreshAfterPractice(completed: false);
      return;
    }
    final action = quickPracticeActionForFurniture(furniture.id);
    if (action == null) return;
    final catalog = _catalog;
    final progressStore = _progressStore;
    if (catalog == null || progressStore == null) {
      _showUnavailable('练习内容还在准备中，请稍后再试');
      return;
    }
    final result = QuickPracticeSelector.select(
      catalog: catalog,
      progress: progressStore.progress,
      action: action,
    );
    if (!result.isAvailable) {
      _showUnavailable(result.reason ?? '当前无法开始三题陪练');
      return;
    }
    final completed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PracticePage(
          selection: selection,
          textbook: textbook,
          quickSession: result.session,
        ),
      ),
    );
    await _refreshAfterPractice(completed: completed == true);
  }

  Future<void> _refreshAfterPractice({required bool completed}) async {
    await _open();
    if (mounted && completed) {
      setState(() => _message = '三题陪练完成，真棒！');
    }
  }

  void _showUnavailable(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String? _furnitureActionDescription(PetFurniture furniture) =>
      switch (furniture.id) {
        'study-desk' => '继续综合练习',
        'bookcase' => '开始三题综合复习',
        'toy-box' => '开始三题错题优先练习',
        'desk-lamp' => '开始三题汉字拼音练习',
        'flower-pot' => '开始三题朗读检查',
        _ => null,
      };

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
          PetRoomScene(
            profile: profile,
            onFurnitureTap: _activateFurniture,
            actionDescription: _furnitureActionDescription,
          ),
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
