import 'package:flutter/material.dart';

import '../models/textbook.dart';
import '../services/textbook_repository.dart';
import 'practice_page.dart';
import 'review_page.dart';

class ModePage extends StatelessWidget {
  const ModePage({super.key, required this.selection, required this.textbook});

  final TextbookSelection selection;
  final Textbook textbook;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(selection.label)),
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
                              selection: selection,
                              textbook: textbook,
                            ),
                          ),
                        ),
                      ),
                      _ModeCard(
                        icon: Icons.edit_note_outlined,
                        title: '练习',
                        description: '看拼音写汉字，或看汉字写拼音；支持错题练习。',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => PracticePage(
                              selection: selection,
                              textbook: textbook,
                            ),
                          ),
                        ),
                      ),
                    ];
                    if (constraints.maxWidth < 620) {
                      return Column(
                        children: [
                          cards[0],
                          const SizedBox(height: 16),
                          cards[1],
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: cards[0]),
                        const SizedBox(width: 18),
                        Expanded(child: cards[1]),
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
