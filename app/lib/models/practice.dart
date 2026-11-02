import 'textbook.dart';

enum PracticeDirection {
  writeHanzi,
  writePinyin,
  listenWriteHanzi,
  readAloud,
  poemDictation,
  poemReadAloud,
  fillBlank,
}

class PracticeQuestion {
  const PracticeQuestion({
    required this.id,
    required this.kind,
    required this.category,
    required this.answerLines,
    required this.promptLines,
    required this.source,
    required this.chapterId,
    this.poemTitle = '',
    this.poemDynasty = '',
    this.poemAuthor = '',
    this.fillBlankOnly = false,
  });

  final String id;
  final String kind;
  final String category;
  final List<String> answerLines;
  final List<String> promptLines;
  final String source;
  final String chapterId;
  final String poemTitle;
  final String poemDynasty;
  final String poemAuthor;
  final bool fillBlankOnly;

  String get answer => answerLines.join('\n');

  String get prompt => promptLines.join('\n');

  bool get isPoem => poemTitle.isNotEmpty;

  String get poemPrompt => [
    if (poemTitle.isNotEmpty) '《$poemTitle》',
    [poemDynasty, poemAuthor].where((value) => value.isNotEmpty).join(' · '),
  ].where((value) => value.isNotEmpty).join('\n');

  bool supportsDirection(PracticeDirection direction) {
    if (fillBlankOnly) return direction == PracticeDirection.fillBlank;
    if (direction == PracticeDirection.fillBlank) return false;
    if (isPoem) {
      return direction == PracticeDirection.poemDictation ||
          direction == PracticeDirection.poemReadAloud;
    }
    if (direction == PracticeDirection.poemDictation ||
        direction == PracticeDirection.poemReadAloud) {
      return false;
    }
    if (direction != PracticeDirection.listenWriteHanzi &&
        direction != PracticeDirection.readAloud) {
      return true;
    }
    const speechCategories = {'词', '引用句子', '诗词'};
    if (!speechCategories.contains(category)) return false;
    return RegExp(r'[\u4E00-\u9FFF]').allMatches(answer).length >= 2;
  }

  String attemptId(PracticeDirection direction) => '$id:${direction.name}';
}

class PracticeCatalog {
  const PracticeCatalog(this.questions);

  final List<PracticeQuestion> questions;

  List<PracticeQuestion> forChapter(String chapterId) => questions
      .where((question) => question.chapterId == chapterId)
      .toList(growable: false);

  factory PracticeCatalog.fromTextbook(Textbook textbook) {
    final questions = <PracticeQuestion>[];
    final seen = <String>{};
    final appendix = textbook.contents
        .where((unit) => unit.id == 'appendix')
        .expand((unit) => unit.chapters);

    for (final table in appendix) {
      for (final entry in table.text) {
        if (entry.id.isEmpty || entry.zh.isEmpty || entry.pinyin.isEmpty) {
          continue;
        }
        final chapterId = entry.introducedChapterId.isNotEmpty
            ? entry.introducedChapterId
            : entry.refs
                  .map((ref) => ref.chapterId)
                  .firstWhere((id) => id.isNotEmpty, orElse: () => '');
        if (chapterId.isEmpty) continue;
        questions.add(
          PracticeQuestion(
            id: 'appendix:${entry.id}',
            kind: table.name,
            category: _appendixCategory(table.id),
            answerLines: [entry.zh],
            promptLines: [entry.pinyin],
            source: table.name,
            chapterId: chapterId,
          ),
        );

        for (final ref in entry.refs) {
          if (ref.segmentId.isEmpty || !seen.add(ref.segmentId)) continue;
          final sentence = textbook.segment(ref.segmentId);
          if (sentence == null ||
              sentence.zh.isEmpty ||
              sentence.pinyin.isEmpty) {
            continue;
          }
          questions.add(
            PracticeQuestion(
              id: 'sentence:${sentence.id}',
              kind: '句子',
              category: '引用句子',
              answerLines: [sentence.zh],
              promptLines: [sentence.pinyin],
              source: textbook.node(ref.workId)?.displayTitle ?? table.name,
              chapterId: ref.chapterId,
            ),
          );
        }
      }
    }

    for (final unit in textbook.contents.where(
      (item) => item.id != 'appendix',
    )) {
      for (final chapter in unit.chapters) {
        for (final node in _descendants(
          chapter,
        ).where((item) => item.contentType == 'poem')) {
          final lines = node.text
              .where((line) => line.zh.isNotEmpty && line.pinyin.isNotEmpty)
              .toList(growable: false);
          final questionId = 'poem:${node.id}';
          if (node.id.isEmpty || lines.isEmpty || !seen.add(questionId)) {
            continue;
          }
          questions.add(
            PracticeQuestion(
              id: questionId,
              kind: '古诗词',
              category: '诗词',
              answerLines: [for (final line in lines) line.zh],
              promptLines: [for (final line in lines) line.pinyin],
              source: node.displayTitle,
              chapterId: chapter.id,
              poemTitle: node.displayTitle,
              poemDynasty: node.dynasty.zh,
              poemAuthor: node.author.zh,
            ),
          );
        }
        // Keep the existing per-line memorization exercises and their IDs so
        // previously accumulated progress remains available. Whole-poem
        // dictation and recitation are additional exercises above.
        for (final node in _descendants(
          chapter,
        ).where((item) => item.memorize)) {
          for (final sentence in node.text) {
            final questionId = 'poem:${sentence.id}';
            if (sentence.id.isEmpty ||
                sentence.zh.isEmpty ||
                sentence.pinyin.isEmpty ||
                !seen.add(questionId)) {
              continue;
            }
            questions.add(
              PracticeQuestion(
                id: questionId,
                kind: '背诵诗词',
                category: '诗词',
                answerLines: [sentence.zh],
                promptLines: [sentence.pinyin],
                source: node.displayTitle,
                chapterId: chapter.id,
              ),
            );
          }
        }
      }
    }
    return PracticeCatalog([
      ...questions,
      for (final question in questions) ..._fillBlankQuestions(question),
    ]);
  }

  static String _appendixCategory(String id) => switch (id) {
    'appendix-recognition' => '字',
    'appendix-writing' => '字',
    'appendix-words' => '词',
    _ => '附录',
  };
}

Iterable<PracticeQuestion> _fillBlankQuestions(
  PracticeQuestion question,
) sync* {
  if (question.category == '词') {
    final characters = _hanziCharacters(question.answer);
    if (characters.length < 2) return;
    final missingCount = (characters.length + 1) ~/ 2;
    final shownCount = characters.length - missingCount;
    yield _fillBlankQuestion(
      source: question,
      idSuffix: 'left',
      promptLines: [
        _wordBlankPrompt(
          missingCount: missingCount,
          shown: characters.skip(missingCount),
          blankFirst: true,
        ),
      ],
      answer: characters.take(missingCount).join(),
    );
    yield _fillBlankQuestion(
      source: question,
      idSuffix: 'right',
      promptLines: [
        _wordBlankPrompt(
          missingCount: missingCount,
          shown: characters.take(shownCount),
          blankFirst: false,
        ),
      ],
      answer: characters.skip(shownCount).join(),
    );
    return;
  }

  if (!question.isPoem || question.answerLines.length < 2) return;
  for (var index = 0; index + 1 < question.answerLines.length; index += 2) {
    final first = question.answerLines[index];
    final second = question.answerLines[index + 1];
    final firstAnswer = _hanziCharacters(first).join();
    final secondAnswer = _hanziCharacters(second).join();
    if (firstAnswer.isEmpty || secondAnswer.isEmpty) continue;
    final pair = index ~/ 2 + 1;
    yield _fillBlankQuestion(
      source: question,
      idSuffix: 'pair-$pair-first',
      promptLines: [_blankHanzi(first), second],
      answer: firstAnswer,
    );
    yield _fillBlankQuestion(
      source: question,
      idSuffix: 'pair-$pair-second',
      promptLines: [first, _blankHanzi(second)],
      answer: secondAnswer,
    );
  }
}

PracticeQuestion _fillBlankQuestion({
  required PracticeQuestion source,
  required String idSuffix,
  required List<String> promptLines,
  required String answer,
}) => PracticeQuestion(
  id: '${source.id}:fill:$idSuffix',
  kind: source.isPoem ? '古诗词填空' : '词语填空',
  category: source.category,
  answerLines: [answer],
  promptLines: promptLines,
  source: source.source,
  chapterId: source.chapterId,
  poemTitle: source.poemTitle,
  poemDynasty: source.poemDynasty,
  poemAuthor: source.poemAuthor,
  fillBlankOnly: true,
);

List<String> _hanziCharacters(String text) => [
  for (final match in RegExp(r'[\u3400-\u9FFF]').allMatches(text))
    match.group(0)!,
];

String _wordBlankPrompt({
  required int missingCount,
  required Iterable<String> shown,
  required bool blankFirst,
}) {
  final blanks = List.filled(missingCount, '＿');
  return [
    if (blankFirst) ...blanks,
    ...shown,
    if (!blankFirst) ...blanks,
  ].join(' ');
}

String _blankHanzi(String text) =>
    text.replaceAll(RegExp(r'[\u3400-\u9FFF]'), '＿');

Iterable<ContentNode> _descendants(ContentNode node) sync* {
  yield node;
  for (final child in node.children) {
    yield* _descendants(child);
  }
}
