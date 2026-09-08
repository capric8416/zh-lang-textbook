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
  final _writingPadKey = GlobalKey<WritingPadState>();
  PracticeCatalog? _catalog;
  PracticeProgressStore? _store;
  PracticeQuestion? _question;
  Object? _loadError;
  PracticeDirection _direction = PracticeDirection.writeHanzi;
  PracticeScope _scope = PracticeScope.all;
  String _category = '全部';

  @override
  void initState() {
    super.initState();
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
        _chooseQuestion();
      });
    } catch (error, stackTrace) {
      debugPrintStack(label: '练习页初始化失败：$error', stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => _loadError = error);
    }
  }

  List<PracticeQuestion> get _available {
    final progress = _store?.progress;
    return (_catalog?.questions ?? const <PracticeQuestion>[]).where((
      question,
    ) {
      final matchesCategory =
          _category == '全部' || question.category == _category;
      if (!matchesCategory || progress == null) return matchesCategory;
      return switch (_scope) {
        PracticeScope.all => true,
        PracticeScope.wrong => progress.isWrong(question.id),
        PracticeScope.completed => progress.isDone(question.id),
      };
    }).toList();
  }

  List<String> get _categories => [
    '全部',
    ...(_catalog?.questions ?? const <PracticeQuestion>[])
        .map((item) => item.category)
        .toSet()
        .toList()
      ..sort(),
  ];

  void _chooseQuestion() {
    final available = _available;
    _question = available.isEmpty
        ? null
        : available[_random.nextInt(available.length)];
    _writingPadKey.currentState?.clear();
  }

  void _updateFilters({PracticeScope? scope, String? category}) {
    setState(() {
      _scope = scope ?? _scope;
      _category = category ?? _category;
      _chooseQuestion();
    });
  }

  Future<void> _showCorrection() async {
    final question = _question;
    if (question == null) return;
    final target = _direction == PracticeDirection.writeHanzi
        ? question.answerLines
        : question.promptLines;
    final hasWriting = _writingPadKey.currentState?.hasWriting ?? false;
    final dialogResult = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('对比参考答案'),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '请逐句对照。手写内容暂不做自动识别，由你确认是否正确。',
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
            child: const Text('需要复习'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('我答对了'),
          ),
        ],
      ),
    );
    if (dialogResult == null || _store == null) return;
    await _store!.record(question.id, correct: dialogResult);
    if (!mounted) return;
    setState(_chooseQuestion);
  }

  @override
  Widget build(BuildContext context) {
    final store = _store;
    final catalog = _catalog;
    if (_loadError != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('语文基础练习')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('练习题加载失败：$_loadError'),
          ),
        ),
      );
    }
    if (store == null || catalog == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final colors = Theme.of(context).colorScheme;
    final question = _question;
    final progress = store.progress;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 48,
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
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _ProgressChip(label: '已练习 ${progress.done.length}'),
                  _ProgressChip(
                    label: '错题 ${progress.wrong.length}',
                    error: true,
                  ),
                  Text(
                    '题库 ${catalog.questions.length}',
                    style: TextStyle(color: colors.onSurfaceVariant),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text('练习范围', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final scope in PracticeScope.values)
                    ChoiceChip(
                      label: Text(switch (scope) {
                        PracticeScope.all => '全部题目',
                        PracticeScope.wrong => '错题练习',
                        PracticeScope.completed => '已练习',
                      }),
                      selected: _scope == scope,
                      onSelected: (_) => _updateFilters(scope: scope),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final category in _categories)
                    FilterChip(
                      label: Text(category),
                      selected: _category == category,
                      onSelected: (_) => _updateFilters(category: category),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              if (question == null)
                _EmptyPractice(
                  scope: _scope,
                  onReset: () => _updateFilters(scope: PracticeScope.all),
                )
              else
                _QuestionCard(
                  question: question,
                  direction: _direction,
                  writingPadKey: _writingPadKey,
                  onDirection: (direction) => setState(() {
                    _direction = direction;
                    _writingPadKey.currentState?.clear();
                  }),
                  onNext: () => setState(_chooseQuestion),
                  onCorrect: _showCorrection,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.question,
    required this.direction,
    required this.writingPadKey,
    required this.onDirection,
    required this.onNext,
    required this.onCorrect,
  });

  final PracticeQuestion question;
  final PracticeDirection direction;
  final GlobalKey<WritingPadState> writingPadKey;
  final ValueChanged<PracticeDirection> onDirection;
  final VoidCallback onNext;
  final VoidCallback onCorrect;

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
            Row(
              children: [
                Chip(label: Text(question.category)),
                const SizedBox(width: 8),
                Text(
                  question.kind,
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
                const Spacer(),
                Text(
                  question.source,
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SegmentedButton<PracticeDirection>(
              segments: const [
                ButtonSegment(
                  value: PracticeDirection.writeHanzi,
                  label: Text('看拼音写汉字'),
                  icon: Icon(Icons.translate),
                ),
                ButtonSegment(
                  value: PracticeDirection.writePinyin,
                  label: Text('看汉字写拼音'),
                  icon: Icon(Icons.text_fields),
                ),
              ],
              selected: {direction},
              onSelectionChanged: (value) => onDirection(value.first),
            ),
            const SizedBox(height: 22),
            Text(
              showPinyin ? '根据拼音书写汉字' : '根据汉字书写拼音',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: colors.primaryContainer.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                prompt.join('\n'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: showPinyin ? 24 : 30,
                  height: 1.8,
                  color: colors.onSurface,
                ),
              ),
            ),
            const SizedBox(height: 20),
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
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: onNext,
                  icon: const Icon(Icons.shuffle),
                  label: const Text('换一题'),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: onCorrect,
                  icon: const Icon(Icons.fact_check_outlined),
                  label: const Text('批改'),
                ),
              ],
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

class _ProgressChip extends StatelessWidget {
  const _ProgressChip({required this.label, this.error = false});

  final String label;
  final bool error;

  @override
  Widget build(BuildContext context) => Chip(
    avatar: Icon(
      error ? Icons.error_outline : Icons.check_circle_outline,
      size: 18,
    ),
    label: Text(label),
  );
}

class _EmptyPractice extends StatelessWidget {
  const _EmptyPractice({required this.scope, required this.onReset});

  final PracticeScope scope;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        children: [
          const Icon(Icons.celebration_outlined, size: 42),
          const SizedBox(height: 12),
          Text(scope == PracticeScope.wrong ? '暂时没有错题' : '这个范围还没有题目'),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onReset, child: const Text('练习全部题目')),
        ],
      ),
    ),
  );
}
