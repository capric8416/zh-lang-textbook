import 'textbook.dart';

enum PracticeDirection { writeHanzi, writePinyin }

enum PracticeScope { all, wrong, completed }

class PracticeQuestion {
  const PracticeQuestion({
    required this.id,
    required this.kind,
    required this.category,
    required this.answerLines,
    required this.promptLines,
    required this.source,
  });

  final String id;
  final String kind;
  final String category;
  final List<String> answerLines;
  final List<String> promptLines;
  final String source;

  String get answer => answerLines.join('\n');

  String get prompt => promptLines.join('\n');
}

class PracticeCatalog {
  const PracticeCatalog(this.questions);

  final List<PracticeQuestion> questions;

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
        questions.add(
          PracticeQuestion(
            id: 'appendix:${entry.id}',
            kind: table.name,
            category: _appendixCategory(table.id),
            answerLines: [entry.zh],
            promptLines: [entry.pinyin],
            source: table.name,
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
            ),
          );
        }
      }
    }

    for (final node in textbook.allNodes.where((item) => item.memorize)) {
      for (final sentence in node.text) {
        if (sentence.id.isEmpty ||
            sentence.zh.isEmpty ||
            sentence.pinyin.isEmpty ||
            !seen.add('poem:${sentence.id}')) {
          continue;
        }
        questions.add(
          PracticeQuestion(
            id: 'poem:${sentence.id}',
            kind: '背诵诗词',
            category: '诗词',
            answerLines: [sentence.zh],
            promptLines: [sentence.pinyin],
            source: node.displayTitle,
          ),
        );
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
