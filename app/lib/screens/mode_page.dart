import 'package:flutter/material.dart';

import '../models/pet.dart';
import '../models/practice.dart';
import '../models/textbook.dart';
import '../services/learning_mastery.dart';
import '../services/pet_growth.dart';
import '../services/practice_progress.dart';
import '../services/textbook_repository.dart';
import '../widgets/pet_growth_card.dart';
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

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    final store = await PracticeProgressStore.open(widget.selection.fileName);
    final catalog = PracticeCatalog.fromTextbook(widget.textbook);
    final petStore = await PetGrowthStore.open();
    final pet = await petStore.synchronize(
      textbookKey: widget.selection.fileName,
      textbook: widget.textbook,
      catalog: catalog,
      progress: store.progress,
      emitCelebrations: false,
    );
    if (mounted) {
      setState(() {
        _wrongCount = store.progress.wrongCountFor(catalog.questions);
        _petProfile = pet.profile;
        _mastery = pet.mastery;
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
                    onOpenHome: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const PetHomePage(),
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
