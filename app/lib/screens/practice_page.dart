import 'dart:math';

import 'package:flutter/material.dart';

import '../models/practice.dart';
import '../models/textbook.dart';
import '../services/practice_progress.dart';
import '../services/textbook_repository.dart';
import '../widgets/writing_pad.dart';

class PracticePage extends StatefulWidget {
  const PracticePage({
    super.key,
    required this.selection,
    required this.textbook,
  });

  final TextbookSelection selection;
  final Textbook textbook;

  @override
  State<PracticePage> createState() => _PracticePageState();
}

class _PracticePageState extends State<PracticePage> {
  final _random = Random();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _writingPadKey = GlobalKey<WritingPadState>();
  late final List<TocChapter> _chapters;
  PracticeCatalog? _catalog;
  PracticeProgressStore? _store;
  PracticeQuestion? _question;
  Object? _loadError;
  late String _selectedChapterId;
  PracticeDirection _direction = PracticeDirection.writeHanzi;
  bool _graded = false;
  bool _selecting = false;

  @override
  void initState() {
    super.initState();
    _chapters = widget.textbook.index
        .where((unit) => unit.id != 'appendix')
        .expand((unit) => unit.chapters)
        .toList(growable: false);
    _selectedChapterId = _chapters.first.id;
    _openProgress();
  }

  Future<void> _openProgress() async {
    try {
      final catalog = PracticeCatalog.fromTextbook(widget.textbook);
      final store = await PracticeProgressStore.open(widget.selection.fileName);
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _store = store;
      });
      await _chooseQuestion();
    } catch (error, stackTrace) {
      debugPrintStack(label: '练习页初始化失败：$error', stackTrace: stackTrace);
      if (mounted) setState(() => _loadError = error);
    }
  }

  Future<void> _chooseQuestion() async {
    final catalog = _catalog;
    final store = _store;
    if (catalog == null || store == null || _selecting) return;
    _selecting = true;
    try {
      var direction = PracticeDirection
          .values[_random.nextInt(PracticeDirection.values.length)];
      var selected = await _selectForDirection(
        catalog.forChapter(_selectedChapterId),
        direction,
        store,
      );
      if (selected == null) {
        direction = direction == PracticeDirection.writeHanzi
            ? PracticeDirection.writePinyin
            : PracticeDirection.writeHanzi;
        selected = await _selectForDirection(
          catalog.forChapter(_selectedChapterId),
          direction,
          store,
        );
      }
      if (!mounted) return;
      setState(() {
        _direction = direction;
        _question = selected;
        _graded = false;
      });
      _writingPadKey.currentState?.clear();
    } finally {
      _selecting = false;
    }
  }

  Future<PracticeQuestion?> _selectForDirection(
    List<PracticeQuestion> questions,
    PracticeDirection direction,
    PracticeProgressStore store,
  ) async {
    final now = DateTime.now();
    final candidates = questions
        .where(
          (question) => !store.isBlocked(question.attemptId(direction), now),
        )
        .toList();
    while (candidates.isNotEmpty) {
      final selected = _weightedChoice(candidates, direction, store);
      if (await store.consumeSkip(selected.attemptId(direction), now)) {
        candidates.remove(selected);
        continue;
      }
      return selected;
    }
    return null;
  }

  PracticeQuestion _weightedChoice(
    List<PracticeQuestion> questions,
    PracticeDirection direction,
    PracticeProgressStore store,
  ) {
    final weights = [
      for (final question in questions)
        store.weight(question.attemptId(direction)),
    ];
    var cursor =
        _random.nextDouble() * weights.fold<double>(0, (a, b) => a + b);
    for (var index = 0; index < questions.length; index++) {
      cursor -= weights[index];
      if (cursor <= 0) return questions[index];
    }
    return questions.last;
  }

  Future<void> _selectChapter(
    String chapterId, {
    required bool closeDrawer,
  }) async {
    if (!_graded && _question != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先批改当前题目，再切换课文。')));
      return;
    }
    if (closeDrawer) _scaffoldKey.currentState?.closeDrawer();
    setState(() {
      _selectedChapterId = chapterId;
      _question = null;
    });
    await _chooseQuestion();
  }

  Future<void> _showCorrection() async {
    final question = _question;
    final store = _store;
    if (question == null || store == null || _graded) return;
    final target = _direction == PracticeDirection.writeHanzi
        ? question.answerLines
        : question.promptLines;
    final hasWriting = _writingPadKey.currentState?.hasWriting ?? false;
    final correct = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('逐句对比参考答案'),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '手写内容暂不做自动识别，请逐句比较后确认结果。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              for (var index = 0; index < target.length; index++) ...[
                _AnswerLine(
                  index: index + 1,
                  answer: target[index],
                  response: hasWriting ? '（已在书写区作答）' : '（未书写）',
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('答错了'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('答对了'),
          ),
        ],
      ),
    );
    if (correct == null) return;
    await store.record(question.attemptId(_direction), correct: correct);
    if (mounted) setState(() => _graded = true);
  }

  String get _unitName => widget.textbook.index
      .firstWhere(
        (unit) =>
            unit.chapters.any((chapter) => chapter.id == _selectedChapterId),
      )
      .name;

  TocChapter get _chapter =>
      _chapters.firstWhere((chapter) => chapter.id == _selectedChapterId);

  @override
  Widget build(BuildContext context) {
    if (_loadError != null) {
      return Scaffold(body: Center(child: Text('练习题加载失败：$_loadError')));
    }
    final catalog = _catalog;
    final store = _store;
    if (catalog == null || store == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        final toc = _PracticeToc(
          textbook: widget.textbook,
          catalog: catalog,
          selectedChapterId: _selectedChapterId,
          onSelect: (id) => _selectChapter(id, closeDrawer: !wide),
        );
        return Scaffold(
          key: _scaffoldKey,
          drawer: wide ? null : Drawer(width: 320, child: SafeArea(child: toc)),
          appBar: AppBar(
            toolbarHeight: 48,
            leadingWidth: wide ? 56 : 88,
            leading: Row(
              children: [
                IconButton(
                  tooltip: '返回',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(width: 40),
                  style: IconButton.styleFrom(
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                if (!wide)
                  IconButton(
                    tooltip: '打开目录',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(width: 40),
                    style: IconButton.styleFrom(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.menu),
                    onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                  ),
              ],
            ),
            title: Row(
              children: [
                const Text('语文基础练习'),
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
          ),
          body: wide
              ? Row(
                  children: [
                    SizedBox(width: 300, child: toc),
                    const VerticalDivider(width: 1),
                    Expanded(child: _buildContent(store)),
                  ],
                )
              : _buildContent(store),
        );
      },
    );
  }

  Widget _buildContent(PracticeProgressStore store) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Text(
        _unitName,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        _chapter.name,
        style: Theme.of(
          context,
        ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 12,
        children: [
          Text('已练习 ${store.progress.completedCount}'),
          Text('当前错题 ${store.progress.wrongCount}'),
          Text('本课题目 ${_catalog!.forChapter(_selectedChapterId).length}'),
        ],
      ),
      const SizedBox(height: 20),
      if (_question == null)
        const Card(
          child: Padding(
            padding: EdgeInsets.all(28),
            child: Text('本课没有可练习题目，或题目尚未到复习时间。'),
          ),
        )
      else
        _QuestionCard(
          question: _question!,
          direction: _direction,
          writingPadKey: _writingPadKey,
          graded: _graded,
          onCorrect: _showCorrection,
          onNext: _graded ? _chooseQuestion : null,
        ),
    ],
  );
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.question,
    required this.direction,
    required this.writingPadKey,
    required this.graded,
    required this.onCorrect,
    required this.onNext,
  });

  final PracticeQuestion question;
  final PracticeDirection direction;
  final GlobalKey<WritingPadState> writingPadKey;
  final bool graded;
  final VoidCallback onCorrect;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final showPinyin = direction == PracticeDirection.writeHanzi;
    final prompt = showPinyin ? question.promptLines : question.answerLines;
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Chip(label: Text(question.category)),
                Text(
                  question.kind,
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
                Text(
                  '· ${question.source}',
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  showPinyin ? Icons.translate : Icons.text_fields,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  showPinyin ? '看拼音写汉字' : '看汉字写拼音',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: colors.primaryContainer.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                prompt.join('\n'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: showPinyin ? 24 : 30, height: 1.8),
              ),
            ),
            const SizedBox(height: 18),
            Text('书写区', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            WritingPad(
              key: writingPadKey,
              grid: showPinyin ? WritingGrid.hanzi : WritingGrid.pinyin,
              slotLengths: _slotLengths(
                showPinyin ? question.answer : question.prompt,
                showPinyin ? WritingGrid.hanzi : WritingGrid.pinyin,
              ),
            ),
            const SizedBox(height: 18),
            Align(
              alignment: Alignment.centerRight,
              child: graded
                  ? FilledButton.icon(
                      onPressed: onNext,
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text('下一题'),
                    )
                  : FilledButton.icon(
                      onPressed: onCorrect,
                      icon: const Icon(Icons.fact_check_outlined),
                      label: const Text('批改'),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  List<int> _slotLengths(String text, WritingGrid grid) {
    if (grid == WritingGrid.hanzi) {
      return [for (final _ in RegExp(r'[\u4E00-\u9FFF]').allMatches(text)) 1];
    }
    return [
      for (final match in RegExp(r'[A-Za-z\u00C0-\u024F]+').allMatches(text))
        match.group(0)?.runes.length ?? 1,
    ];
  }
}

class _PracticeToc extends StatelessWidget {
  const _PracticeToc({
    required this.textbook,
    required this.catalog,
    required this.selectedChapterId,
    required this.onSelect,
  });

  final Textbook textbook;
  final PracticeCatalog catalog;
  final String selectedChapterId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(8, 12, 8, 24),
        children: [
          const ListTile(
            leading: CircleAvatar(child: Icon(Icons.edit_note_outlined)),
            title: Text('练习目录', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          for (final unit in textbook.index.where(
            (item) => item.id != 'appendix',
          ))
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
                for (final chapter in unit.chapters)
                  _PracticeTocTile(
                    chapter: chapter,
                    count: catalog.forChapter(chapter.id).length,
                    selected: chapter.id == selectedChapterId,
                    onTap: () => onSelect(chapter.id),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _PracticeTocTile extends StatelessWidget {
  const _PracticeTocTile({
    required this.chapter,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final TocChapter chapter;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 8, 3),
      child: Material(
        color: selected ? colors.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: ListTile(
          dense: true,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          leading: chapter.no == null ? null : Text('${chapter.no}'),
          title: Text(
            chapter.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Text('$count', style: TextStyle(color: colors.outline)),
          onTap: onTap,
        ),
      ),
    );
  }
}

class _AnswerLine extends StatelessWidget {
  const _AnswerLine({
    required this.index,
    required this.response,
    required this.answer,
  });

  final int index;
  final String response;
  final String answer;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('第 $index 句', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 6),
          Text('你的作答：$response'),
          const Divider(height: 20),
          Text(
            '参考答案：$answer',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    ),
  );
}
