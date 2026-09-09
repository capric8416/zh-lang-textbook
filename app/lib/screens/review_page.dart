import 'package:flutter/material.dart';

import '../models/textbook.dart';
import '../services/textbook_repository.dart';
import '../widgets/ruby_text.dart';

enum ReviewMode { review, practice }

class ReviewPage extends StatefulWidget {
  const ReviewPage({
    super.key,
    required this.selection,
    required this.textbook,
    this.mode = ReviewMode.review,
  });

  final TextbookSelection selection;
  final Textbook textbook;
  final ReviewMode mode;

  @override
  State<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends State<ReviewPage> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _focusedWorkKey = GlobalKey();
  final _scrollController = ScrollController();
  late final List<TocChapter> _chapters;
  late String _selectedChapterId;
  String? _focusedWorkId;

  String get _pageTitle =>
      widget.mode == ReviewMode.practice ? '语文基础练习' : '语文基础复习';

  @override
  void initState() {
    super.initState();
    _chapters = widget.textbook.index
        .expand((unit) => unit.chapters)
        .where((chapter) => widget.textbook.chapter(chapter.id) != null)
        .toList();
    _selectedChapterId = _chapters.first.id;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  int get _selectedIndex =>
      _chapters.indexWhere((chapter) => chapter.id == _selectedChapterId);

  void _select(String chapterId, {String? workId, bool closeDrawer = false}) {
    final chapterChanged = chapterId != _selectedChapterId;
    setState(() {
      _selectedChapterId = chapterId;
      _focusedWorkId = workId;
    });
    if (closeDrawer) _scaffoldKey.currentState?.closeDrawer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (workId != null) {
        final target = _focusedWorkKey.currentContext;
        if (target != null) {
          Scrollable.ensureVisible(
            target,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
            alignment: 0.08,
          );
        }
      } else if (chapterChanged && _scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
    });
  }

  void _goRelative(int offset) {
    final targetIndex = _selectedIndex + offset;
    if (targetIndex < 0 || targetIndex >= _chapters.length) return;
    _select(_chapters[targetIndex].id);
  }

  @override
  Widget build(BuildContext context) {
    final chapter = widget.textbook.chapter(_selectedChapterId)!;
    final selectedIndex = _selectedIndex;
    final previous = selectedIndex > 0 ? _chapters[selectedIndex - 1] : null;
    final next = selectedIndex + 1 < _chapters.length
        ? _chapters[selectedIndex + 1]
        : null;
    final unitName = widget.textbook.index
        .firstWhere(
          (unit) => unit.chapters.any((item) => item.id == _selectedChapterId),
        )
        .name;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final toc = _TableOfContents(
          textbook: widget.textbook,
          selectedChapterId: _selectedChapterId,
          selectedWorkId: _focusedWorkId,
          onSelect: (chapterId, workId) =>
              _select(chapterId, workId: workId, closeDrawer: !wide),
        );
        return Scaffold(
          key: _scaffoldKey,
          drawer: wide ? null : Drawer(width: 320, child: SafeArea(child: toc)),
          appBar: AppBar(
            toolbarHeight: 48,
            leadingWidth: wide ? 56 : 88,
            leading: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: '返回',
                  icon: const Icon(Icons.arrow_back),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(width: 40),
                  style: IconButton.styleFrom(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                if (!wide)
                  IconButton(
                    tooltip: '打开目录',
                    icon: const Icon(Icons.menu),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(width: 40),
                    style: IconButton.styleFrom(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                  ),
              ],
            ),
            title: Row(
              children: [
                Text(_pageTitle),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    widget.selection.label,
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
              ],
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.error,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text('知识点'),
                  ],
                ),
              ),
            ],
          ),
          body: wide
              ? Row(
                  children: [
                    SizedBox(width: 300, child: toc),
                    const VerticalDivider(width: 1),
                    Expanded(
                      child: _ReviewChapter(
                        key: ValueKey(_selectedChapterId),
                        unitName: unitName,
                        chapter: chapter,
                        highlights: widget.textbook.highlights,
                        focusedWorkId: _focusedWorkId,
                        focusedWorkKey: _focusedWorkKey,
                        scrollController: _scrollController,
                        previous: previous,
                        next: next,
                        onPrevious: previous == null
                            ? null
                            : () => _goRelative(-1),
                        onNext: next == null ? null : () => _goRelative(1),
                      ),
                    ),
                  ],
                )
              : _ReviewChapter(
                  key: ValueKey(_selectedChapterId),
                  unitName: unitName,
                  chapter: chapter,
                  highlights: widget.textbook.highlights,
                  focusedWorkId: _focusedWorkId,
                  focusedWorkKey: _focusedWorkKey,
                  scrollController: _scrollController,
                  previous: previous,
                  next: next,
                  onPrevious: previous == null ? null : () => _goRelative(-1),
                  onNext: next == null ? null : () => _goRelative(1),
                ),
        );
      },
    );
  }
}

class _TableOfContents extends StatelessWidget {
  const _TableOfContents({
    required this.textbook,
    required this.selectedChapterId,
    required this.selectedWorkId,
    required this.onSelect,
  });

  final Textbook textbook;
  final String selectedChapterId;
  final String? selectedWorkId;
  final void Function(String chapterId, String? workId) onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: colors.primary,
                  foregroundColor: colors.onPrimary,
                  child: const Text('文'),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    '课本目录',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          for (final unit in textbook.index)
            ExpansionTile(
              key: PageStorageKey(unit.id),
              initiallyExpanded: unit.chapters.any(
                (chapter) => chapter.id == selectedChapterId,
              ),
              title: Text(
                unit.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              children: [
                for (final chapter in unit.chapters) ...[
                  _TocTile(
                    selected:
                        chapter.id == selectedChapterId &&
                        selectedWorkId == null,
                    leading: chapter.no?.toString(),
                    title: chapter.name,
                    page: chapter.page,
                    onTap: () => onSelect(chapter.id, null),
                  ),
                  for (final child in chapter.children)
                    _TocTile(
                      selected: child.id == selectedWorkId,
                      title: child.name,
                      page: child.page,
                      nested: true,
                      onTap: () => onSelect(chapter.id, child.id),
                    ),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _TocTile extends StatelessWidget {
  const _TocTile({
    required this.selected,
    required this.title,
    required this.onTap,
    this.leading,
    this.page,
    this.nested = false,
  });

  final bool selected;
  final String title;
  final String? leading;
  final int? page;
  final bool nested;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(left: nested ? 30 : 12, right: 8, bottom: 3),
      child: Material(
        color: selected ? colors.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            child: Row(
              children: [
                if (leading != null)
                  SizedBox(
                    width: 26,
                    child: Text(
                      leading!,
                      style: TextStyle(
                        color: selected ? colors.primary : colors.outline,
                        fontSize: 12,
                      ),
                    ),
                  )
                else if (nested)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Icon(
                      Icons.subdirectory_arrow_right,
                      size: 15,
                      color: colors.outline,
                    ),
                  ),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? colors.onPrimaryContainer : null,
                      fontWeight: selected ? FontWeight.w600 : null,
                    ),
                  ),
                ),
                if (page != null)
                  Text(
                    '$page',
                    style: TextStyle(color: colors.outline, fontSize: 11),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ReviewChapter extends StatelessWidget {
  const _ReviewChapter({
    super.key,
    required this.unitName,
    required this.chapter,
    required this.highlights,
    required this.focusedWorkId,
    required this.focusedWorkKey,
    required this.scrollController,
    required this.previous,
    required this.next,
    required this.onPrevious,
    required this.onNext,
  });

  final String unitName;
  final ContentNode chapter;
  final HighlightIndex highlights;
  final String? focusedWorkId;
  final GlobalKey focusedWorkKey;
  final ScrollController scrollController;
  final TocChapter? previous;
  final TocChapter? next;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: scrollController,
      child: SingleChildScrollView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  unitName,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (chapter.no != null) ...[
                      CircleAvatar(
                        radius: 19,
                        backgroundColor: Theme.of(
                          context,
                        ).colorScheme.primaryContainer,
                        child: Text(
                          '${chapter.no}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: Text(
                        chapter.name,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (chapter.memorize)
                      const Chip(
                        avatar: Icon(Icons.auto_stories_outlined, size: 17),
                        label: Text('背诵'),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                if (chapter.contentType == 'appendix')
                  _AppendixGrid(chapter: chapter)
                else ...[
                  if (chapter.text.isNotEmpty || !chapter.title.isEmpty)
                    _ContentSection(node: chapter, highlights: highlights),
                  for (final child in chapter.children)
                    Padding(
                      key: child.id == focusedWorkId ? focusedWorkKey : null,
                      padding: const EdgeInsets.only(bottom: 18),
                      child: _ContentSection(
                        node: child,
                        highlights: highlights,
                        card: true,
                      ),
                    ),
                ],
                const SizedBox(height: 20),
                _LessonPager(
                  previous: previous,
                  next: next,
                  onPrevious: onPrevious,
                  onNext: onNext,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LessonPager extends StatelessWidget {
  const _LessonPager({
    required this.previous,
    required this.next,
    required this.onPrevious,
    required this.onNext,
  });

  final TocChapter? previous;
  final TocChapter? next;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.only(top: 18),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.outlineVariant)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _PagerLink(
              direction: '上一课',
              chapter: previous,
              icon: Icons.arrow_back,
              onTap: onPrevious,
              alignment: Alignment.centerLeft,
            ),
          ),
          Expanded(
            child: _PagerLink(
              direction: '下一课',
              chapter: next,
              icon: Icons.arrow_forward,
              onTap: onNext,
              alignment: Alignment.centerRight,
            ),
          ),
        ],
      ),
    );
  }
}

class _PagerLink extends StatelessWidget {
  const _PagerLink({
    required this.direction,
    required this.chapter,
    required this.icon,
    required this.onTap,
    required this.alignment,
  });

  final String direction;
  final TocChapter? chapter;
  final IconData icon;
  final VoidCallback? onTap;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: alignment,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon == Icons.arrow_back) ...[
                Icon(
                  icon,
                  size: 18,
                  color: onTap == null ? colors.outline : colors.primary,
                ),
                const SizedBox(width: 8),
              ],
              Column(
                crossAxisAlignment: alignment == Alignment.centerLeft
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.end,
                children: [
                  Text(
                    direction,
                    style: TextStyle(
                      color: onTap == null ? colors.outline : colors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (chapter != null)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: Text(
                        chapter!.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                ],
              ),
              if (icon == Icons.arrow_forward) ...[
                const SizedBox(width: 8),
                Icon(
                  icon,
                  size: 18,
                  color: onTap == null ? colors.outline : colors.primary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ContentSection extends StatelessWidget {
  const _ContentSection({
    required this.node,
    required this.highlights,
    this.card = false,
  });

  final ContentNode node;
  final HighlightIndex highlights;
  final bool card;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: EdgeInsets.all(card ? 22 : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!node.topic.isEmpty && node.topic.zh != node.title.zh) ...[
            RubyText(
              text: node.topic.zh,
              pinyin: node.topic.pinyin,
              highlights: highlights.forField(node.id, 'topic'),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            const SizedBox(height: 12),
          ],
          if (!node.title.isEmpty) ...[
            RubyText(
              text: node.title.zh,
              pinyin: node.title.pinyin,
              highlights: highlights.forField(node.id, 'title'),
              fontSize: node.contentType == 'exercise' ? 22 : 30,
              fontWeight: FontWeight.w700,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
          ],
          if (!node.author.isEmpty || !node.dynasty.isEmpty) ...[
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 14,
              runSpacing: 8,
              children: [
                if (!node.dynasty.isEmpty)
                  RubyText(
                    text: node.dynasty.zh,
                    pinyin: node.dynasty.pinyin,
                    highlights: highlights.forField(node.id, 'dynasty'),
                    fontSize: 15,
                  ),
                if (!node.author.isEmpty)
                  RubyText(
                    text: node.author.zh,
                    pinyin: node.author.pinyin,
                    highlights: highlights.forField(node.id, 'author'),
                    fontSize: 15,
                  ),
              ],
            ),
            const SizedBox(height: 20),
          ],
          for (final segment in node.text)
            Padding(
              padding: const EdgeInsets.only(bottom: 15),
              child: RubyText(
                text: segment.zh,
                pinyin: segment.pinyin,
                highlights: highlights.forSegment(segment.id),
                fontSize: node.contentType == 'poem' ? 25 : 21,
                textAlign: node.contentType == 'poem'
                    ? TextAlign.center
                    : TextAlign.start,
              ),
            ),
        ],
      ),
    );
    if (!card) return content;
    return Card(elevation: 0, child: content);
  }
}

class _AppendixGrid extends StatelessWidget {
  const _AppendixGrid({required this.chapter});

  final ContentNode chapter;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final item in chapter.text)
          Card(
            elevation: 0,
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: RubyText(
                text: item.zh,
                pinyin: item.pinyin,
                fontSize: item.zh.runes.length == 1 ? 24 : 19,
              ),
            ),
          ),
      ],
    );
  }
}
