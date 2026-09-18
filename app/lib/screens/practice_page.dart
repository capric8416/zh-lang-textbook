import 'dart:math';

import 'package:flutter/material.dart';

import '../models/ocr.dart';
import '../models/practice.dart';
import '../models/quick_practice.dart';
import '../models/speech_assessment.dart';
import '../models/textbook.dart';
import '../services/ocr_engine.dart';
import '../services/pet_growth.dart';
import '../services/practice_progress.dart';
import '../services/quick_practice.dart';
import '../services/speech_engine.dart';
import '../services/textbook_repository.dart';
import '../widgets/writing_pad.dart';
import '../widgets/pet_celebration.dart';

class PracticePage extends StatefulWidget {
  const PracticePage({
    super.key,
    required this.selection,
    required this.textbook,
    this.mistakesOnly = false,
    this.quickSession,
  });

  final TextbookSelection selection;
  final Textbook textbook;
  final bool mistakesOnly;
  final QuickPracticeSession? quickSession;

  @override
  State<PracticePage> createState() => _PracticePageState();
}

class _PracticePageState extends State<PracticePage> {
  static const _allMistakes = '__all_mistakes__';

  final _random = Random();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _writingPadKey = GlobalKey<WritingPadState>();
  late final List<TocChapter> _chapters;
  PracticeCatalog? _catalog;
  PracticeProgressStore? _store;
  PetGrowthStore? _petStore;
  PracticeQuestion? _question;
  Object? _loadError;
  late String _selectedChapterId;
  late String _regularChapterId;
  late bool _mistakesOnly;
  PracticeDirection _direction = PracticeDirection.writeHanzi;
  bool _graded = false;
  bool _grading = false;
  bool _selecting = false;
  bool _playing = false;
  bool _recording = false;
  int _quickIndex = 0;

  @override
  void initState() {
    super.initState();
    _chapters = widget.textbook.index
        .where((unit) => unit.id != 'appendix')
        .expand((unit) => unit.chapters)
        .toList(growable: false);
    _regularChapterId = _chapters.first.id;
    _mistakesOnly = widget.mistakesOnly;
    _selectedChapterId = _mistakesOnly ? _allMistakes : _regularChapterId;
    _openProgress();
  }

  @override
  void dispose() {
    if (_recording) SpeechEngine.instance.cancelRecording();
    super.dispose();
  }

  Future<void> _openProgress() async {
    try {
      final catalog = PracticeCatalog.fromTextbook(widget.textbook);
      final store = await PracticeProgressStore.open(widget.selection.fileName);
      final petStore = await PetGrowthStore.open();
      await petStore.synchronize(
        textbookKey: widget.selection.fileName,
        textbook: widget.textbook,
        catalog: catalog,
        progress: store.progress,
        emitCelebrations: false,
      );
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _store = store;
        _petStore = petStore;
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
      final quickSession = widget.quickSession;
      if (quickSession != null) {
        final attempt = quickSession.attempts[_quickIndex];
        final selected = catalog.questions
            .where((question) => question.id == attempt.questionId)
            .firstOrNull;
        if (!mounted) return;
        setState(() {
          _direction = attempt.direction;
          _question = selected;
          _graded = false;
        });
        _writingPadKey.currentState?.clear();
        return;
      }
      final directions = PracticeDirection.values.toList()..shuffle(_random);
      final questions = _selectedChapterId == _allMistakes
          ? catalog.questions
          : catalog.forChapter(_selectedChapterId);
      var direction = directions.first;
      PracticeQuestion? selected;
      for (final candidateDirection in directions) {
        final candidate = await _selectForDirection(
          questions,
          candidateDirection,
          store,
        );
        if (candidate != null) {
          direction = candidateDirection;
          selected = candidate;
          break;
        }
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
          (question) =>
              question.supportsDirection(direction) &&
              (_mistakesOnly
                  ? store.progress
                        .forQuestion(question.attemptId(direction))
                        .isWrong
                  : !store.isBlocked(question.attemptId(direction), now)),
        )
        .toList();
    while (candidates.isNotEmpty) {
      final selected = _weightedChoice(candidates, direction, store);
      if (!_mistakesOnly &&
          await store.consumeSkip(selected.attemptId(direction), now)) {
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
    if (!_mistakesOnly && !_graded && _question != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先批改当前题目，再切换课文。')));
      return;
    }
    if (closeDrawer) _scaffoldKey.currentState?.closeDrawer();
    setState(() {
      _selectedChapterId = chapterId;
      if (chapterId != _allMistakes) _regularChapterId = chapterId;
      _question = null;
    });
    await _chooseQuestion();
  }

  Future<void> _setMistakesOnly(bool value) async {
    if (_mistakesOnly == value) return;
    setState(() {
      _mistakesOnly = value;
      _selectedChapterId = value ? _allMistakes : _regularChapterId;
      _question = null;
      _graded = false;
    });
    _writingPadKey.currentState?.clear();
    await _chooseQuestion();
  }

  Future<void> _showCorrection() async {
    final question = _question;
    final store = _store;
    final writingPad = _writingPadKey.currentState;
    if (question == null || store == null || _graded || _grading) return;
    if (writingPad == null || !writingPad.hasWriting) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先在书写区作答。')));
      return;
    }
    setState(() => _grading = true);
    try {
      final images = await writingPad.renderForOcr();
      final recognized = await OcrEngine.instance.recognizeAll(images);
      final expected = _direction != PracticeDirection.writePinyin
          ? _hanziSlots(question.answer)
          : _pinyinSlots(question.prompt);
      final comparisons = [
        for (var index = 0; index < expected.length; index++)
          _OcrComparison(
            expected: expected[index],
            recognized: index < recognized.length ? recognized[index] : '',
            correct:
                _normalizeAnswer(expected[index], _direction) ==
                _normalizeAnswer(
                  index < recognized.length ? recognized[index] : '',
                  _direction,
                ),
          ),
      ];
      if (!mounted) return;
      final correct = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) =>
            _CorrectionDialog(images: images, comparisons: comparisons),
      );
      if (correct == null) {
        if (mounted) setState(() => _grading = false);
        return;
      }
      await store.record(question.attemptId(_direction), correct: correct);
      if (!mounted) return;
      setState(() {
        _graded = true;
        _grading = false;
      });
      await _syncPetGrowth();
    } catch (error, stackTrace) {
      debugPrintStack(label: 'OCR 批改失败：$error', stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => _grading = false);
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('OCR 批改失败'),
          content: Text('$error'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _playDictation() async {
    final question = _question;
    if (question == null || _playing) return;
    setState(() => _playing = true);
    try {
      await SpeechEngine.instance.speak(
        pinyin: question.prompt,
        cacheKey: '${widget.selection.fileName}:${question.id}',
      );
    } catch (error, stackTrace) {
      debugPrintStack(label: '听写语音播放失败：$error', stackTrace: stackTrace);
      if (mounted) _showSpeechError('语音播放失败', error);
    } finally {
      if (mounted) setState(() => _playing = false);
    }
  }

  Future<void> _toggleReadAloud() async {
    final question = _question;
    final store = _store;
    if (question == null || store == null || _graded || _grading) return;
    if (!_recording) {
      try {
        await SpeechEngine.instance.startRecording();
        if (mounted) setState(() => _recording = true);
      } catch (error, stackTrace) {
        debugPrintStack(label: '朗读录音失败：$error', stackTrace: stackTrace);
        if (mounted) _showSpeechError('无法开始录音', error);
      }
      return;
    }

    setState(() {
      _recording = false;
      _grading = true;
    });
    try {
      final assessment = await SpeechEngine.instance.stopAndAssess(
        expectedText: question.answer,
        expectedPinyin: question.prompt,
      );
      if (!mounted) return;
      final correct = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _SpeechReviewDialog(
          expectedText: question.answer,
          assessment: assessment,
        ),
      );
      if (correct == null) return;
      await store.record(question.attemptId(_direction), correct: correct);
      if (mounted) {
        setState(() => _graded = true);
        await _syncPetGrowth();
      }
    } catch (error, stackTrace) {
      debugPrintStack(label: '朗读检查失败：$error', stackTrace: stackTrace);
      if (mounted) _showSpeechError('朗读检查失败', error);
    } finally {
      if (mounted) setState(() => _grading = false);
    }
  }

  Future<void> _showSpeechError(String title, Object error) => showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text('$error'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    ),
  );

  Future<void> _syncPetGrowth() async {
    final store = _store;
    final petStore = _petStore;
    final catalog = _catalog;
    if (store == null || petStore == null || catalog == null) return;
    final result = await petStore.synchronize(
      textbookKey: widget.selection.fileName,
      textbook: widget.textbook,
      catalog: catalog,
      progress: store.progress,
      emitCelebrations: true,
    );
    if (mounted && result.celebrations.isNotEmpty) {
      await showPetCelebrations(
        context,
        result.celebrations,
        petName: result.profile.name,
      );
    }
  }

  Future<void> _advanceQuickPractice() async {
    final session = widget.quickSession;
    if (session == null) {
      await _chooseQuestion();
      return;
    }
    if (_quickIndex == session.attempts.length - 1) {
      if (mounted) Navigator.of(context).pop(true);
      return;
    }
    setState(() => _quickIndex += 1);
    await _chooseQuestion();
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
        final quick = widget.quickSession != null;
        final toc = _PracticeToc(
          textbook: widget.textbook,
          catalog: catalog,
          progress: store.progress,
          mistakesOnly: _mistakesOnly,
          selectedChapterId: _selectedChapterId,
          onSelect: (id) => _selectChapter(id, closeDrawer: !wide),
        );
        return Scaffold(
          key: _scaffoldKey,
          drawer: wide || quick
              ? null
              : Drawer(width: 320, child: SafeArea(child: toc)),
          appBar: AppBar(
            toolbarHeight: 48,
            leadingWidth: wide || quick ? 56 : 88,
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
                if (!wide && !quick)
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
                Text(
                  quick
                      ? '宠物三题陪练'
                      : _mistakesOnly
                      ? '错题专项'
                      : '语文基础练习',
                ),
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
          body: wide && !quick
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
        widget.quickSession != null
            ? widget.selection.label
            : _mistakesOnly
            ? _selectedChapterId == _allMistakes
                  ? widget.selection.label
                  : _unitName
            : _unitName,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        widget.quickSession != null
            ? quickPracticeActionLabel(widget.quickSession!.action)
            : _mistakesOnly && _selectedChapterId == _allMistakes
            ? '整本教材错题专项'
            : _chapter.name,
        style: Theme.of(
          context,
        ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (widget.quickSession != null)
            QuickPracticeProgressIndicator(
              current: _quickIndex + 1,
              total: widget.quickSession!.attempts.length,
            )
          else
            Text('已练习 ${store.progress.completedCount}'),
          if (widget.quickSession == null) ...[
            ActionChip(
              avatar: const Icon(Icons.assignment_late_outlined, size: 18),
              label: Text(
                '当前错题 ${store.progress.wrongCountFor(_catalog!.questions)}',
              ),
              onPressed: _mistakesOnly ? null : () => _setMistakesOnly(true),
            ),
            if (_mistakesOnly)
              ActionChip(
                avatar: const Icon(Icons.edit_note_outlined, size: 18),
                label: const Text('返回综合练习'),
                onPressed: () => _setMistakesOnly(false),
              )
            else
              Text('本课题目 ${_catalog!.forChapter(_selectedChapterId).length}'),
          ],
        ],
      ),
      const SizedBox(height: 20),
      if (_question == null)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Text(
              _mistakesOnly ? '当前范围没有错题，去综合练习看看。' : '本课没有可练习题目，或题目尚未到复习时间。',
            ),
          ),
        )
      else
        _QuestionCard(
          question: _question!,
          direction: _direction,
          writingPadKey: _writingPadKey,
          graded: _graded,
          grading: _grading,
          playing: _playing,
          recording: _recording,
          onCorrect: _showCorrection,
          onPlay: _playDictation,
          onReadAloud: _toggleReadAloud,
          nextLabel:
              widget.quickSession != null &&
                  _quickIndex == widget.quickSession!.attempts.length - 1
              ? '完成陪练'
              : '下一题',
          onNext: _graded ? _advanceQuickPractice : null,
        ),
    ],
  );
}

class QuickPracticeProgressIndicator extends StatelessWidget {
  const QuickPracticeProgressIndicator({
    super.key,
    required this.current,
    required this.total,
  });

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) => Chip(
    key: const ValueKey('quick-practice-progress'),
    avatar: const Icon(Icons.pets_outlined, size: 18),
    label: Text('$current/$total'),
  );
}

class _QuestionCard extends StatelessWidget {
  const _QuestionCard({
    required this.question,
    required this.direction,
    required this.writingPadKey,
    required this.graded,
    required this.grading,
    required this.playing,
    required this.recording,
    required this.onCorrect,
    required this.onPlay,
    required this.onReadAloud,
    required this.onNext,
    required this.nextLabel,
  });

  final PracticeQuestion question;
  final PracticeDirection direction;
  final GlobalKey<WritingPadState> writingPadKey;
  final bool graded;
  final bool grading;
  final bool playing;
  final bool recording;
  final VoidCallback onCorrect;
  final VoidCallback onPlay;
  final VoidCallback onReadAloud;
  final VoidCallback? onNext;
  final String nextLabel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final writesHanzi =
        direction == PracticeDirection.writeHanzi ||
        direction == PracticeDirection.listenWriteHanzi;
    final isDictation = direction == PracticeDirection.listenWriteHanzi;
    final isReadAloud = direction == PracticeDirection.readAloud;
    final prompt = direction == PracticeDirection.writeHanzi
        ? question.promptLines
        : question.answerLines;
    final title = switch (direction) {
      PracticeDirection.writeHanzi => '看拼音写汉字',
      PracticeDirection.writePinyin => '看汉字写拼音',
      PracticeDirection.listenWriteHanzi => '听音写汉字',
      PracticeDirection.readAloud => '朗读检查',
    };
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
                  isDictation
                      ? Icons.hearing
                      : isReadAloud
                      ? Icons.mic_outlined
                      : direction == PracticeDirection.writeHanzi
                      ? Icons.translate
                      : Icons.text_fields,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(title, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: colors.primaryContainer.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(14),
              ),
              child: isDictation
                  ? Center(
                      child: FilledButton.tonalIcon(
                        onPressed: playing ? null : onPlay,
                        icon: playing
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.volume_up_outlined),
                        label: Text(playing ? '正在生成并播放…' : '播放听写语音'),
                      ),
                    )
                  : Text(
                      prompt.join('\n'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: direction == PracticeDirection.writeHanzi
                            ? 24
                            : 30,
                        height: 1.8,
                      ),
                    ),
            ),
            if (isReadAloud) ...[
              const SizedBox(height: 12),
              Text(
                '仅检查朗读内容是否匹配，并非严格的发音评分；识别结果需要人工复核。',
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
            ] else ...[
              const SizedBox(height: 18),
              WritingPad(
                key: writingPadKey,
                grid: writesHanzi ? WritingGrid.hanzi : WritingGrid.pinyin,
                slotLengths: _slotLengths(
                  writesHanzi ? question.answer : question.prompt,
                  writesHanzi ? WritingGrid.hanzi : WritingGrid.pinyin,
                ),
              ),
            ],
            const SizedBox(height: 18),
            Align(
              alignment: Alignment.centerRight,
              child: graded
                  ? FilledButton.icon(
                      onPressed: onNext,
                      icon: const Icon(Icons.arrow_forward),
                      label: Text(nextLabel),
                    )
                  : FilledButton.icon(
                      onPressed: grading
                          ? null
                          : isReadAloud
                          ? onReadAloud
                          : onCorrect,
                      icon: grading
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Icon(
                              isReadAloud
                                  ? recording
                                        ? Icons.stop_circle_outlined
                                        : Icons.mic_outlined
                                  : Icons.fact_check_outlined,
                            ),
                      label: Text(
                        grading
                            ? '识别中…'
                            : isReadAloud
                            ? recording
                                  ? '结束并检查'
                                  : '开始朗读'
                            : '批改',
                      ),
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

int _wrongCountForQuestions(
  Iterable<PracticeQuestion> questions,
  PracticeProgress progress,
) => progress.wrongCountFor(questions);

class _PracticeToc extends StatelessWidget {
  const _PracticeToc({
    required this.textbook,
    required this.catalog,
    required this.progress,
    required this.mistakesOnly,
    required this.selectedChapterId,
    required this.onSelect,
  });

  final Textbook textbook;
  final PracticeCatalog catalog;
  final PracticeProgress progress;
  final bool mistakesOnly;
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
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.edit_note_outlined)),
            title: Text(
              mistakesOnly ? '错题目录' : '练习目录',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          if (mistakesOnly)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 8, 8),
              child: Material(
                color: selectedChapterId == _PracticePageState._allMistakes
                    ? colors.primaryContainer
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.library_books_outlined),
                  title: const Text('全部错题'),
                  trailing: Text(
                    '${progress.wrongCountFor(catalog.questions)}',
                  ),
                  onTap: () => onSelect(_PracticePageState._allMistakes),
                ),
              ),
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
                    count: mistakesOnly
                        ? _wrongCountForQuestions(
                            catalog.forChapter(chapter.id),
                            progress,
                          )
                        : catalog.forChapter(chapter.id).length,
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

class _SpeechReviewDialog extends StatefulWidget {
  const _SpeechReviewDialog({
    required this.expectedText,
    required this.assessment,
  });

  final String expectedText;
  final SpeechAssessment assessment;

  @override
  State<_SpeechReviewDialog> createState() => _SpeechReviewDialogState();
}

class _SpeechReviewDialogState extends State<_SpeechReviewDialog> {
  late bool _correct = widget.assessment.automaticallyCorrect;

  @override
  Widget build(BuildContext context) {
    final assessment = widget.assessment;
    final percent = (assessment.matchRate * 100).round();
    return AlertDialog(
      title: const Text('朗读检查'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('这是内容匹配结果，不是严格的发音评分。请听者人工复核。'),
              const SizedBox(height: 16),
              _SpeechResultRow(label: '朗读内容', value: widget.expectedText),
              _SpeechResultRow(
                label: '识别文本',
                value: assessment.recognizedText.isEmpty
                    ? '（未识别）'
                    : assessment.recognizedText,
              ),
              _SpeechResultRow(label: '目标拼音', value: assessment.expectedPinyin),
              _SpeechResultRow(
                label: '识别拼音',
                value: assessment.recognizedPinyin.isEmpty
                    ? '（未识别）'
                    : assessment.recognizedPinyin,
              ),
              const SizedBox(height: 10),
              Text(
                '汉字/拼音匹配：${assessment.matchedSyllables}/'
                '${assessment.totalSyllables}（$percent%）',
              ),
              const SizedBox(height: 14),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.check_circle_outline),
                    label: Text('复核为正确'),
                  ),
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.cancel_outlined),
                    label: Text('需要复习'),
                  ),
                ],
                selected: {_correct},
                onSelectionChanged: (value) =>
                    setState(() => _correct = value.single),
              ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context, _correct),
          child: const Text('确认'),
        ),
      ],
    );
  }
}

class _SpeechResultRow extends StatelessWidget {
  const _SpeechResultRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 76,
          child: Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(child: SelectableText(value)),
      ],
    ),
  );
}

class _CorrectionDialog extends StatefulWidget {
  const _CorrectionDialog({required this.images, required this.comparisons});

  final List<OcrImage> images;
  final List<_OcrComparison> comparisons;

  @override
  State<_CorrectionDialog> createState() => _CorrectionDialogState();
}

class _CorrectionDialogState extends State<_CorrectionDialog> {
  late final List<bool> _reviewed = [
    for (final comparison in widget.comparisons) comparison.correct,
  ];

  bool get _correct => _reviewed.isNotEmpty && _reviewed.every((item) => item);

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_correct ? '批改结果：正确' : '批改结果：需要复习'),
    content: SizedBox(
      width: 720,
      child: SingleChildScrollView(
        child: _OcrComparisonTable(
          images: widget.images,
          comparisons: widget.comparisons,
          reviewed: _reviewed,
          onReviewChanged: (index, correct) =>
              setState(() => _reviewed[index] = correct),
        ),
      ),
    ),
    actions: [
      FilledButton(
        onPressed: () => Navigator.pop(context, _correct),
        child: const Text('确认'),
      ),
    ],
  );
}

class _OcrComparisonTable extends StatelessWidget {
  const _OcrComparisonTable({
    required this.images,
    required this.comparisons,
    required this.reviewed,
    required this.onReviewChanged,
  });

  final List<OcrImage> images;
  final List<_OcrComparison> comparisons;
  final List<bool> reviewed;
  final void Function(int index, bool correct) onReviewChanged;

  @override
  Widget build(BuildContext context) {
    final widths = [
      for (var index = 0; index < comparisons.length; index++)
        _columnWidth(index),
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final lines = _wrapColumns(
              widths,
              max(72.0, constraints.maxWidth - 72),
            );
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var line = 0; line < lines.length; line++) ...[
                  if (line > 0) const Divider(height: 20),
                  _comparisonBlock(context, lines[line], widths),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _comparisonBlock(
    BuildContext context,
    List<int> indices,
    List<double> widths,
  ) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(
        width: 72,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ResultRowLabel('用户书写', height: 60),
            SizedBox(height: 4),
            _ResultRowLabel('识别结果', height: 38),
            SizedBox(height: 4),
            _ResultRowLabel('正确结果', height: 38),
            SizedBox(height: 4),
            _ResultRowLabel('复核结果', height: 38),
          ],
        ),
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _resultRow(indices, widths, (index) {
            final image = images[index];
            return Padding(
              padding: const EdgeInsets.all(4),
              child: Image.memory(
                image.previewPng,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            );
          }, height: 60),
          const SizedBox(height: 4),
          _resultRow(
            indices,
            widths,
            (index) => _OcrResultCell(comparison: comparisons[index]),
            height: 38,
          ),
          const SizedBox(height: 4),
          _resultRow(
            indices,
            widths,
            (index) => Center(
              child: Text(
                comparisons[index].expected,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            height: 38,
          ),
          const SizedBox(height: 4),
          _resultRow(
            indices,
            widths,
            (index) => _ReviewResultCell(
              correct: reviewed[index],
              automaticallyCorrect: comparisons[index].correct,
              onChanged: (correct) => onReviewChanged(index, correct),
            ),
            height: 38,
          ),
        ],
      ),
    ],
  );

  List<List<int>> _wrapColumns(List<double> widths, double maxWidth) {
    final lines = <List<int>>[];
    var current = <int>[];
    var usedWidth = 0.0;
    for (var index = 0; index < widths.length; index++) {
      final addedWidth = widths[index] + (current.isEmpty ? 0 : 8);
      if (current.isNotEmpty && usedWidth + addedWidth > maxWidth) {
        lines.add(current);
        current = <int>[];
        usedWidth = 0;
      }
      usedWidth += widths[index] + (current.isEmpty ? 0 : 8);
      current.add(index);
    }
    if (current.isNotEmpty) lines.add(current);
    return lines;
  }

  double _columnWidth(int index) {
    if (index >= images.length) return 72;
    final image = images[index];
    return (72 * image.width / image.height).clamp(72.0, 160.0).toDouble();
  }

  Widget _resultRow(
    List<int> indices,
    List<double> widths,
    Widget Function(int index) builder, {
    required double height,
  }) => Row(
    children: [
      for (var position = 0; position < indices.length; position++) ...[
        SizedBox(
          width: widths[indices[position]],
          height: height,
          child: builder(indices[position]),
        ),
        if (position != indices.length - 1) const SizedBox(width: 8),
      ],
    ],
  );
}

class _ReviewResultCell extends StatelessWidget {
  const _ReviewResultCell({
    required this.correct,
    required this.automaticallyCorrect,
    required this.onChanged,
  });

  final bool correct;
  final bool automaticallyCorrect;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = automaticallyCorrect
        ? colors.onSurfaceVariant
        : correct
        ? colors.primary
        : colors.error;
    final backgroundColor = automaticallyCorrect
        ? colors.surfaceContainerHighest
        : color.withValues(alpha: 0.08);
    return Tooltip(
      message: automaticallyCorrect
          ? '自动识别正确'
          : correct
          ? '点击改回错误'
          : '点击复核为正确',
      child: Material(
        color: backgroundColor,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: color.withValues(alpha: 0.45)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: automaticallyCorrect ? null : () => onChanged(!correct),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                correct ? Icons.check_circle : Icons.cancel,
                size: 16,
                color: color,
              ),
              const SizedBox(width: 4),
              Text(correct ? '正确' : '改正确'),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultRowLabel extends StatelessWidget {
  const _ResultRowLabel(this.text, {required this.height});

  final String text;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(text, style: Theme.of(context).textTheme.labelLarge),
    ),
  );
}

class _OcrResultCell extends StatelessWidget {
  const _OcrResultCell({required this.comparison});

  final _OcrComparison comparison;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = comparison.correct ? colors.primary : colors.error;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(
        children: [
          Center(
            child: Text(
              comparison.recognized.isEmpty ? '未识别' : comparison.recognized,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Positioned(
            top: 3,
            right: 3,
            child: Icon(
              comparison.correct ? Icons.check_circle : Icons.cancel,
              color: color,
              size: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _OcrComparison {
  const _OcrComparison({
    required this.expected,
    required this.recognized,
    required this.correct,
  });

  final String expected;
  final String recognized;
  final bool correct;
}

List<String> _hanziSlots(String text) => [
  for (final match in RegExp(r'[\u4E00-\u9FFF]').allMatches(text))
    match.group(0)!,
];

List<String> _pinyinSlots(String text) => [
  for (final match in RegExp(r'[A-Za-z\u00C0-\u024F]+').allMatches(text))
    match.group(0)!,
];

String _normalizeAnswer(String text, PracticeDirection direction) {
  final pattern = direction != PracticeDirection.writePinyin
      ? RegExp(r'[\u4E00-\u9FFF]')
      : RegExp(r'[A-Za-z\u00C0-\u024F]');
  return pattern
      .allMatches(text)
      .map((match) => match.group(0)!)
      .join()
      .toLowerCase();
}
