import 'package:flutter/material.dart';
import '../models/pet.dart';
import '../models/engagement_event.dart';
import '../models/pet_mission.dart';
import '../models/practice.dart';
import '../models/quick_practice.dart';
import '../models/textbook.dart';
import '../services/pet_growth.dart';
import '../services/engagement_events.dart';
import '../services/learning_mastery.dart';
import '../services/pet_companion.dart';
import '../services/pet_invitation_scheduler.dart';
import '../services/practice_progress.dart';
import '../services/quick_practice.dart';
import '../services/textbook_repository.dart';
import '../widgets/pet_room_scene.dart';
import '../widgets/pet_quick_reaction.dart';
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
  PetCompanionGuide? _guide;
  PetInvitationSchedule? _invitationSchedule;
  PetDailyCompanion? _dailyCompanion;
  EngagementEventStore? _engagementStore;
  String? _surfaceEventId;
  String? _invitationFlowId;
  String? _invitationEventId;
  final _goalPresentation = GoalPresentationLifecycle();
  String _message = '选一个喜欢的伙伴吧';
  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    final store = await PetGrowthStore.open();
    final engagementStore =
        _engagementStore ?? await EngagementEventStore.open();
    final visit = await store.recordVisit(DateTime.now());
    final selection = widget.selection;
    final textbook = widget.textbook;
    final progressStore = selection == null
        ? null
        : await PracticeProgressStore.open(selection.fileName);
    final catalog = textbook == null
        ? null
        : PracticeCatalog.fromTextbook(textbook);
    final mastery = textbook == null || catalog == null || progressStore == null
        ? null
        : calculateTextbookMastery(
            textbook: textbook,
            catalog: catalog,
            progress: progressStore.progress,
          );
    if (!mounted) return;
    _surfaceEventId ??= engagementStore.newId();
    await engagementStore.append(
      eventId: _surfaceEventId,
      type: EngagementEventType.companionSurfaceViewed,
      context: EngagementEventContext(
        textbookKey: selection?.fileName,
        surface: EngagementSurface.petHome,
        roomId: store.profile.selectedRoom,
      ),
    );
    if (visit == PetVisitTransition.nextDay) {
      await engagementStore.append(
        type: EngagementEventType.nextDayReturn,
        context: EngagementEventContext(
          textbookKey: selection?.fileName,
          surface: EngagementSurface.petHome,
          roomId: store.profile.selectedRoom,
        ),
      );
    }
    final guide = mastery == null || catalog == null || progressStore == null
        ? null
        : PetCompanionGuide.build(
            profile: store.profile,
            mastery: mastery,
            catalog: catalog,
            progress: progressStore.progress,
          );
    final schedule = guide == null || selection == null
        ? null
        : PetInvitationScheduler.evaluate(
            guide: guide,
            events: engagementStore.events,
            textbookKey: selection.fileName,
            now: DateTime.now(),
          );
    if (guide?.learningGoal != null) {
      await engagementStore.append(
        eventId: _goalPresentation.eventIdFor(
          guide!.learningGoal!.id,
          engagementStore.newId,
        ),
        type: EngagementEventType.goalViewed,
        context: EngagementEventContext(
          textbookKey: selection?.fileName,
          surface: EngagementSurface.petHome,
          roomId: store.profile.selectedRoom,
          goalKind: guide.learningGoal!.kind,
          goalId: guide.learningGoal!.id,
          goalProgress: guide.learningGoal!.current,
        ),
      );
    } else {
      _goalPresentation.clear();
    }
    if (schedule?.canPresent == true) {
      _invitationFlowId ??= engagementStore.newId();
      _invitationEventId ??= engagementStore.newId();
      await engagementStore.append(
        eventId: _invitationEventId,
        type: EngagementEventType.invitationPresented,
        context: EngagementEventContext(
          textbookKey: selection?.fileName,
          surface: EngagementSurface.petHome,
          launchSource: EngagementLaunchSource.invitation,
          quickPracticeAction: schedule!.invitation!.action,
          roomId: store.profile.selectedRoom,
          flowId: _invitationFlowId,
        ),
      );
    }
    if (!mounted) return;
    setState(() {
      _store = store;
      _progressStore = progressStore;
      _catalog = catalog;
      _guide = guide;
      _invitationSchedule = schedule;
      _engagementStore = engagementStore;
      _dailyCompanion = PetDailyCompanion.build(
        profile: store.profile,
        anonymousInstallId: engagementStore.anonymousInstallId,
        date: DateTime.now(),
      );
      if (_message == '选一个喜欢的伙伴吧') {
        _message = _dailyCompanion!.greeting;
      }
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
    await _openQuickPractice(result.session!, action, furniture: furniture);
  }

  Future<void> _acceptInvitation() async {
    final invitation = _invitationSchedule?.invitation;
    if (invitation == null) return;
    await _openQuickPractice(invitation.session, invitation.action);
    _invitationFlowId = null;
    _invitationEventId = null;
  }

  Future<void> _openGoal() async {
    final guide = _guide;
    final goal = guide?.learningGoal;
    final eventStore = _engagementStore;
    final selection = widget.selection;
    final textbook = widget.textbook;
    if (guide == null ||
        goal == null ||
        eventStore == null ||
        selection == null ||
        textbook == null) {
      _showUnavailable('请从教材学习页进入目标练习');
      return;
    }
    final flowId = eventStore.newId();
    await eventStore.append(
      eventId: eventStore.newId(),
      type: EngagementEventType.goalPracticeStarted,
      context: EngagementEventContext(
        textbookKey: selection.fileName,
        surface: EngagementSurface.petHome,
        launchSource: EngagementLaunchSource.goal,
        goalKind: goal.kind,
        goalId: goal.id,
        goalProgress: goal.current,
        roomId: _store?.profile.selectedRoom,
        flowId: flowId,
      ),
    );
    final goalSession = guide.goalSelection;
    if (goalSession?.session == null) {
      if (!mounted) return;
      _showUnavailable('${goalSession?.reason ?? '当前目标不足 3 题'}，已进入本课普通练习');
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => PracticePage(
            selection: selection,
            textbook: textbook,
            initialChapterId: goal.chapterIds.firstOrNull,
          ),
        ),
      );
      await _open();
      return;
    }
    await _openQuickPractice(
      goalSession!.session!,
      goal.action,
      source: PetMissionSource.goal,
      flowId: flowId,
    );
  }

  Future<void> _skipInvitation() async {
    final store = _engagementStore;
    final invitation = _invitationSchedule?.invitation;
    if (store == null || invitation == null) return;
    await store.append(
      eventId: store.newId(),
      type: EngagementEventType.invitationSkipped,
      context: EngagementEventContext(
        textbookKey: widget.selection?.fileName,
        surface: EngagementSurface.petHome,
        launchSource: EngagementLaunchSource.invitation,
        quickPracticeAction: invitation.action,
        roomId: _store?.profile.selectedRoom,
        flowId: _invitationFlowId,
      ),
    );
    if (mounted) await _open();
  }

  Future<void> _openQuickPractice(
    QuickPracticeSession session,
    QuickPracticeAction action, {
    PetFurniture? furniture,
    PetMissionSource? source,
    String? flowId,
  }) async {
    final selection = widget.selection;
    final textbook = widget.textbook;
    final profile = _store?.profile;
    final eventStore = _engagementStore;
    if (selection == null ||
        textbook == null ||
        profile == null ||
        eventStore == null) {
      return;
    }
    final resolvedSource =
        source ??
        (furniture == null
            ? PetMissionSource.invitation
            : PetMissionSource.furniture);
    final resolvedFlowId =
        flowId ??
        (furniture == null
            ? _invitationFlowId ?? eventStore.newId()
            : eventStore.newId());
    final mission = PetCompanionMission.forQuickPractice(
      action: action,
      petName: profile.name,
      furnitureId: furniture?.id,
      unlockedFurniture: profile.unlockedFurniture,
      source: resolvedSource,
    );
    final completed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PracticePage(
          selection: selection,
          textbook: textbook,
          quickSession: session,
          quickLaunch: QuickPracticeLaunch(
            mission: mission,
            flowId: resolvedFlowId,
            source: resolvedSource,
            roomId: profile.selectedRoom,
            furnitureId: furniture?.id,
          ),
          engagementStore: eventStore,
        ),
      ),
    );
    await _refreshAfterPractice(completed: completed == true);
    final updatedProfile = _store?.profile;
    if (mounted && completed == true && updatedProfile != null) {
      showPetQuickReaction(context, profile: updatedProfile, action: action);
    }
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

  Future<void> _renamePet() async {
    final store = _store;
    if (store == null) return;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _RenamePetDialog(initialName: store.profile.name),
    );
    if (name == null || !await store.rename(name) || !mounted) return;
    await _open();
    if (mounted) setState(() => _message = '以后就叫我$name吧！');
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
            petAlignmentX: _dailyCompanion?.alignmentX ?? 0,
            onFurnitureTap: _activateFurniture,
            actionDescription: _furnitureActionDescription,
            onRevealShown: (id) async {
              await store.acknowledgeFurnitureReveal(id);
              if (mounted) setState(() {});
            },
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        profile.name,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      IconButton(
                        key: const ValueKey('rename-pet'),
                        tooltip: '修改宠物名字',
                        onPressed: _renamePet,
                        icon: const Icon(Icons.edit_outlined),
                      ),
                    ],
                  ),
                  Text(
                    _message,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    '成长值 ${profile.growthPoints} · 大阶段 ${profile.majorStage}',
                  ),
                  if (_guide != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _guide!.goal,
                      key: const ValueKey('pet-next-unlock'),
                      textAlign: TextAlign.center,
                    ),
                    if (_guide!.learningGoal != null) ...[
                      const SizedBox(height: 12),
                      Card(
                        key: const ValueKey('pet-home-learning-goal'),
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          leading: Icon(
                            _guide!.learningGoal!.isComplete
                                ? Icons.check_circle_outline
                                : Icons.flag_outlined,
                          ),
                          title: Text(
                            _guide!.learningGoal!.isComplete
                                ? '目标完成：${_guide!.learningGoal!.unitName}'
                                : _guide!.goalSelection?.isAvailable == false
                                ? '进入本课练习'
                                : _guide!.learningGoal!.actionLabel,
                          ),
                          subtitle: Text(
                            _guide!.learningGoal!.isComplete
                                ? _guide!.learningGoal!.outcome
                                : '${_guide!.learningGoal!.progressLabel}，还差 ${_guide!.learningGoal!.remaining} 个小目标',
                          ),
                          trailing: SizedBox(
                            width: 72,
                            child: LinearProgressIndicator(
                              value: _guide!.learningGoal!.progress,
                              minHeight: 7,
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                          onTap: _openGoal,
                        ),
                      ),
                    ],
                    if (_invitationSchedule?.canPresent == true)
                      FilledButton.tonalIcon(
                        key: const ValueKey('pet-home-invitation'),
                        onPressed: _acceptInvitation,
                        icon: const Icon(Icons.pets_outlined),
                        label: Text(_invitationSchedule!.invitation!.message),
                      ),
                    if (_invitationSchedule?.canPresent == true)
                      TextButton(
                        onPressed: _skipInvitation,
                        child: const Text('稍后再说'),
                      ),
                  ],
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

class _RenamePetDialog extends StatefulWidget {
  const _RenamePetDialog({required this.initialName});

  final String initialName;

  @override
  State<_RenamePetDialog> createState() => _RenamePetDialogState();
}

class _RenamePetDialogState extends State<_RenamePetDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final normalized = normalizePetName(_controller.text);
    if (normalized == null) {
      setState(() => _error = '请输入一个名字');
    } else {
      Navigator.pop(context, normalized);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('给伙伴取名字'),
    content: TextField(
      key: const ValueKey('pet-name-field'),
      controller: _controller,
      autofocus: true,
      maxLength: 8,
      decoration: InputDecoration(labelText: '宠物名字', errorText: _error),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _submit, child: const Text('保存')),
    ],
  );
}
