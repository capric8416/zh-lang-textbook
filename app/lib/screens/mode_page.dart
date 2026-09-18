import 'package:flutter/material.dart';

import '../models/pet.dart';
import '../models/engagement_event.dart';
import '../models/pet_mission.dart';
import '../models/practice.dart';
import '../models/textbook.dart';
import '../services/learning_mastery.dart';
import '../services/engagement_events.dart';
import '../services/pet_growth.dart';
import '../services/pet_companion.dart';
import '../services/pet_invitation_scheduler.dart';
import '../services/practice_progress.dart';
import '../services/textbook_repository.dart';
import '../widgets/pet_growth_card.dart';
import '../widgets/pet_quick_reaction.dart';
import 'practice_page.dart';
import 'review_page.dart';
import 'pet_home_page.dart';

class ModePage extends StatefulWidget {
  const ModePage({super.key, required this.selection, required this.textbook});

  final TextbookSelection selection;
  final Textbook textbook;

  @override
  State<ModePage> createState() => _ModePageState();
}

class _ModePageState extends State<ModePage> {
  int? _wrongCount;
  PetProfile? _petProfile;
  TextbookMastery? _mastery;
  PetCompanionGuide? _guide;
  PetInvitationSchedule? _invitationSchedule;
  PetDailyCompanion? _dailyCompanion;
  EngagementEventStore? _engagementStore;
  String? _surfaceEventId;
  String? _invitationFlowId;
  String? _invitationEventId;
  final _goalPresentation = GoalPresentationLifecycle();

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    final store = await PracticeProgressStore.open(widget.selection.fileName);
    final catalog = PracticeCatalog.fromTextbook(widget.textbook);
    final petStore = await PetGrowthStore.open();
    final engagementStore =
        _engagementStore ?? await EngagementEventStore.open();
    final visit = await petStore.recordVisit(DateTime.now());
    final pet = await petStore.synchronize(
      textbookKey: widget.selection.fileName,
      textbook: widget.textbook,
      catalog: catalog,
      progress: store.progress,
      emitCelebrations: false,
    );
    if (mounted) {
      _surfaceEventId ??= engagementStore.newId();
      await engagementStore.append(
        eventId: _surfaceEventId,
        type: EngagementEventType.companionSurfaceViewed,
        context: EngagementEventContext(
          textbookKey: widget.selection.fileName,
          surface: EngagementSurface.modePage,
        ),
      );
      if (visit == PetVisitTransition.nextDay) {
        await engagementStore.append(
          type: EngagementEventType.nextDayReturn,
          context: EngagementEventContext(
            textbookKey: widget.selection.fileName,
            surface: EngagementSurface.modePage,
          ),
        );
      }
      final guide = PetCompanionGuide.build(
        profile: pet.profile,
        mastery: pet.mastery,
        catalog: catalog,
        progress: store.progress,
      );
      final schedule = PetInvitationScheduler.evaluate(
        guide: guide,
        events: engagementStore.events,
        textbookKey: widget.selection.fileName,
        now: DateTime.now(),
      );
      if (guide.learningGoal != null) {
        await engagementStore.append(
          eventId: _goalPresentation.eventIdFor(
            guide.learningGoal!.id,
            engagementStore.newId,
          ),
          type: EngagementEventType.goalViewed,
          context: EngagementEventContext(
            textbookKey: widget.selection.fileName,
            surface: EngagementSurface.modePage,
            goalKind: guide.learningGoal!.kind,
            goalId: guide.learningGoal!.id,
            goalProgress: guide.learningGoal!.current,
          ),
        );
      } else {
        _goalPresentation.clear();
      }
      if (schedule.canPresent) {
        _invitationFlowId ??= engagementStore.newId();
        _invitationEventId ??= engagementStore.newId();
        await engagementStore.append(
          eventId: _invitationEventId,
          type: EngagementEventType.invitationPresented,
          context: EngagementEventContext(
            textbookKey: widget.selection.fileName,
            surface: EngagementSurface.modePage,
            launchSource: EngagementLaunchSource.invitation,
            quickPracticeAction: schedule.invitation!.action,
            flowId: _invitationFlowId,
          ),
        );
      }
      if (!mounted) return;
      setState(() {
        _wrongCount = store.progress.wrongCountFor(catalog.questions);
        _petProfile = pet.profile;
        _mastery = pet.mastery;
        _guide = guide;
        _invitationSchedule = schedule;
        _engagementStore = engagementStore;
        _dailyCompanion = PetDailyCompanion.build(
          profile: pet.profile,
          anonymousInstallId: engagementStore.anonymousInstallId,
          date: DateTime.now(),
        );
      });
    }
  }

  Future<void> _openPractice({required bool mistakesOnly}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PracticePage(
          selection: widget.selection,
          textbook: widget.textbook,
          mistakesOnly: mistakesOnly,
        ),
      ),
    );
    await _loadDashboard();
  }

  Future<void> _acceptInvitation() async {
    final invitation = _invitationSchedule?.invitation;
    final profile = _petProfile;
    final eventStore = _engagementStore;
    if (invitation == null || profile == null || eventStore == null) return;
    final flowId = _invitationFlowId ?? eventStore.newId();
    final completed = await _pushQuickPractice(
      invitation: invitation,
      profile: profile,
      eventStore: eventStore,
      flowId: flowId,
      source: PetMissionSource.invitation,
    );
    _invitationFlowId = null;
    _invitationEventId = null;
    await _loadDashboard();
    final updatedProfile = _petProfile;
    if (mounted && completed == true && updatedProfile != null) {
      showPetQuickReaction(
        context,
        profile: updatedProfile,
        action: invitation.action,
      );
    }
  }

  Future<void> _openGoal() async {
    final guide = _guide;
    final goal = guide?.learningGoal;
    final profile = _petProfile;
    final eventStore = _engagementStore;
    if (guide == null ||
        goal == null ||
        profile == null ||
        eventStore == null) {
      return;
    }
    final flowId = eventStore.newId();
    await eventStore.append(
      eventId: eventStore.newId(),
      type: EngagementEventType.goalPracticeStarted,
      context: EngagementEventContext(
        textbookKey: widget.selection.fileName,
        surface: EngagementSurface.modePage,
        launchSource: EngagementLaunchSource.goal,
        goalKind: goal.kind,
        goalId: goal.id,
        goalProgress: goal.current,
        flowId: flowId,
      ),
    );
    final selection = guide.goalSelection;
    if (selection?.session == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${selection?.reason ?? '当前目标不足 3 题'}，已进入本课普通练习'),
        ),
      );
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => PracticePage(
            selection: widget.selection,
            textbook: widget.textbook,
            initialChapterId: goal.chapterIds.firstOrNull,
          ),
        ),
      );
      await _loadDashboard();
      return;
    }
    final invitation = PetPracticeInvitation(
      action: goal.action,
      session: selection!.session!,
      message: goal.actionLabel,
    );
    final completed = await _pushQuickPractice(
      invitation: invitation,
      profile: profile,
      eventStore: eventStore,
      flowId: flowId,
      source: PetMissionSource.goal,
    );
    await _loadDashboard();
    final updatedProfile = _petProfile;
    if (mounted && completed == true && updatedProfile != null) {
      showPetQuickReaction(
        context,
        profile: updatedProfile,
        action: goal.action,
      );
    }
  }

  Future<bool?> _pushQuickPractice({
    required PetPracticeInvitation invitation,
    required PetProfile profile,
    required EngagementEventStore eventStore,
    required String flowId,
    required PetMissionSource source,
  }) async {
    if (!mounted) return null;
    final mission = PetCompanionMission.forQuickPractice(
      action: invitation.action,
      petName: profile.name,
      unlockedFurniture: profile.unlockedFurniture,
      source: source,
    );
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PracticePage(
          selection: widget.selection,
          textbook: widget.textbook,
          quickSession: invitation.session,
          quickLaunch: QuickPracticeLaunch(
            mission: mission,
            flowId: flowId,
            source: source,
            roomId: profile.selectedRoom,
          ),
          engagementStore: eventStore,
        ),
      ),
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
        textbookKey: widget.selection.fileName,
        surface: EngagementSurface.modePage,
        launchSource: EngagementLaunchSource.invitation,
        quickPracticeAction: invitation.action,
        flowId: _invitationFlowId,
      ),
    );
    if (mounted) await _loadDashboard();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.selection.label)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Column(
              children: [
                Text(
                  '今天想怎样学习？',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 20),
                if (_petProfile != null && _mastery != null)
                  PetGrowthCard(
                    profile: _petProfile!,
                    mastery: _mastery!,
                    goal: _guide?.goal,
                    greeting: _dailyCompanion?.greeting,
                    invitation: _invitationSchedule?.canPresent == true
                        ? _invitationSchedule!.invitation!.message
                        : null,
                    onAcceptInvitation: _acceptInvitation,
                    onSkipInvitation: _skipInvitation,
                    learningGoal: _guide?.learningGoal,
                    goalActionLabel: _guide?.goalSelection?.isAvailable == false
                        ? '进入本课练习'
                        : null,
                    onOpenGoal: _openGoal,
                    onOpenHome: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => PetHomePage(
                            selection: widget.selection,
                            textbook: widget.textbook,
                          ),
                        ),
                      );
                      await _loadDashboard();
                    },
                  )
                else
                  const LinearProgressIndicator(),
                const SizedBox(height: 28),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final cards = [
                      _ModeCard(
                        icon: Icons.menu_book_outlined,
                        title: '复习',
                        description: '按教材目录阅读正文，查看拼音和知识点标记。',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ReviewPage(
                              selection: widget.selection,
                              textbook: widget.textbook,
                            ),
                          ),
                        ),
                      ),
                      _ModeCard(
                        icon: Icons.edit_note_outlined,
                        title: '练习',
                        description: '看拼音写汉字、听写或朗读，按课文综合练习。',
                        onTap: () => _openPractice(mistakesOnly: false),
                      ),
                      _ModeCard(
                        icon: Icons.assignment_late_outlined,
                        title: '错题专项',
                        description: _wrongCount == null
                            ? '正在读取错题…'
                            : _wrongCount == 0
                            ? '目前没有错题，先去综合练习看看。'
                            : '集中练习整本教材的 $_wrongCount 道当前错题。',
                        onTap: _wrongCount == null || _wrongCount == 0
                            ? null
                            : () => _openPractice(mistakesOnly: true),
                      ),
                    ];
                    if (constraints.maxWidth < 760) {
                      return Column(
                        children: [
                          cards[0],
                          const SizedBox(height: 16),
                          cards[1],
                          const SizedBox(height: 16),
                          cards[2],
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: cards[0]),
                        const SizedBox(width: 18),
                        Expanded(child: cards[1]),
                        const SizedBox(width: 18),
                        Expanded(child: cards[2]),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.description,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: colors.primaryContainer,
                child: Icon(icon, size: 30, color: colors.onPrimaryContainer),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                description,
                style: TextStyle(color: colors.onSurfaceVariant, height: 1.6),
              ),
              if (onTap != null) ...[
                const SizedBox(height: 24),
                Icon(Icons.arrow_forward, color: colors.primary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
