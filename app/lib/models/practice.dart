import 'textbook.dart';

enum PracticeDirection {
  writeHanzi,
  writePinyin,
  listenWriteHanzi,
  readAloud,
  poemDictation,
  poemReadAloud,
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

  String get answer => answerLines.join('\n');

  String get prompt => promptLines.join('\n');

  bool get isPoem => poemTitle.isNotEmpty;

  String get poemPrompt => [
    if (poemTitle.isNotEmpty) '《$poemTitle》',
    [poemDynasty, poemAuthor].where((value) => value.isNotEmpty).join(' · '),
  ].where((value) => value.isNotEmpty).join('\n');

  bool supportsDirection(PracticeDirection direction) {
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
    return PracticeCatalog(questions);
  }

  static String _appendixCategory(String id) => switch (id) {
    'appendix-recognition' => '字',
    'appendix-writing' => '字',
    'appendix-words' => '词',
    _ => '附录',
  };
}

Iterable<ContentNode> _descendants(ContentNode node) sync* {
  yield node;
  for (final child in node.children) {
    yield* _descendants(child);
  }
}
