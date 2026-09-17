import 'package:lpinyin/lpinyin.dart';

class SpeechAssessment {
  const SpeechAssessment({
    required this.recognizedText,
    required this.expectedPinyin,
    required this.recognizedPinyin,
    required this.matchedSyllables,
    required this.totalSyllables,
  });

  factory SpeechAssessment.compare({
    required String expectedText,
    required String expectedPinyin,
    required String recognizedText,
  }) {
    final expectedChars = _hanziCharacters(expectedText);
    final expected = pinyinSyllables(expectedPinyin);
    final recognizedPinyin = PinyinHelper.getPinyinE(
      recognizedText,
      separator: ' ',
      defPinyin: '',
      format: PinyinFormat.WITH_TONE_MARK,
    );
    final recognizedChars = _hanziCharacters(recognizedText);
    final recognized = pinyinSyllables(recognizedPinyin);
    final alignment = _align(
      expectedChars,
      expected,
      recognizedChars,
      recognized,
    );
    final correctedText = StringBuffer();
    final correctedPinyin = <String>[];
    for (final pair in alignment) {
      if (pair.expectedIndex == null) {
        correctedText.write(recognizedChars[pair.recognizedIndex!]);
        correctedPinyin.add(_pinyinAt(recognized, pair.recognizedIndex!));
        continue;
      }
      if (pair.recognizedIndex == null) continue;
      final expectedIndex = pair.expectedIndex!;
      final recognizedIndex = pair.recognizedIndex!;
      if (_matches(
        expectedChars,
        expected,
        recognizedChars,
        recognized,
        expectedIndex,
        recognizedIndex,
      )) {
        correctedText.write(expectedChars[expectedIndex]);
        correctedPinyin.add(_pinyinAt(expected, expectedIndex));
      } else {
        correctedText.write(recognizedChars[recognizedIndex]);
        correctedPinyin.add(_pinyinAt(recognized, recognizedIndex));
      }
    }
    final matched = alignment
        .where(
          (pair) => pair.expectedIndex != null && pair.recognizedIndex != null,
        )
        .where(
          (pair) => _matches(
            expectedChars,
            expected,
            recognizedChars,
            recognized,
            pair.expectedIndex!,
            pair.recognizedIndex!,
          ),
        )
        .length;
    return SpeechAssessment(
      recognizedText: correctedText.toString(),
      expectedPinyin: expected.join(' '),
      recognizedPinyin: correctedPinyin.join(' '),
      matchedSyllables: matched,
      totalSyllables: expected.length,
    );
  }

  final String recognizedText;
  final String expectedPinyin;
  final String recognizedPinyin;
  final int matchedSyllables;
  final int totalSyllables;

  bool get automaticallyCorrect =>
      totalSyllables > 0 &&
      matchedSyllables == totalSyllables &&
      pinyinSyllables(recognizedPinyin).length == totalSyllables;

  double get matchRate =>
      totalSyllables == 0 ? 0 : matchedSyllables / totalSyllables;
}

class _Pair {
  const _Pair(this.expectedIndex, this.recognizedIndex);

  final int? expectedIndex;
  final int? recognizedIndex;
}

List<_Pair> _align(
  List<String> expectedChars,
  List<String> expectedPinyin,
  List<String> recognizedChars,
  List<String> recognizedPinyin,
) {
  final rows = expectedChars.length + 1;
  final columns = recognizedChars.length + 1;
  final scores = List.generate(rows, (_) => List<int>.filled(columns, 0));
  for (var row = expectedChars.length - 1; row >= 0; row--) {
    for (var column = recognizedChars.length - 1; column >= 0; column--) {
      final diagonal =
          scores[row + 1][column + 1] +
          (_matches(
                expectedChars,
                expectedPinyin,
                recognizedChars,
                recognizedPinyin,
                row,
                column,
              )
              ? 1
              : 0);
      scores[row][column] = diagonal >= scores[row + 1][column]
          ? (diagonal >= scores[row][column + 1]
                ? diagonal
                : scores[row][column + 1])
          : scores[row + 1][column];
    }
  }
  final result = <_Pair>[];
  var row = 0;
  var column = 0;
  while (row < expectedChars.length && column < recognizedChars.length) {
    final diagonal =
        scores[row + 1][column + 1] +
        (_matches(
              expectedChars,
              expectedPinyin,
              recognizedChars,
              recognizedPinyin,
              row,
              column,
            )
            ? 1
            : 0);
    if (diagonal == scores[row][column]) {
      result.add(_Pair(row, column));
      row++;
      column++;
    } else if (scores[row + 1][column] >= scores[row][column + 1]) {
      result.add(_Pair(row, null));
      row++;
    } else {
      result.add(_Pair(null, column));
      column++;
    }
  }
  while (row < expectedChars.length) {
    result.add(_Pair(row++, null));
  }
  while (column < recognizedChars.length) {
    result.add(_Pair(null, column++));
  }
  return result;
}

bool _matches(
  List<String> expectedChars,
  List<String> expectedPinyin,
  List<String> recognizedChars,
  List<String> recognizedPinyin,
  int expectedIndex,
  int recognizedIndex,
) {
  return expectedChars[expectedIndex] == recognizedChars[recognizedIndex] ||
      _pinyinAt(expectedPinyin, expectedIndex) ==
          _pinyinAt(recognizedPinyin, recognizedIndex);
}

String _pinyinAt(List<String> pinyin, int index) =>
    index < pinyin.length ? pinyin[index] : '';

List<String> _hanziCharacters(String value) => RegExp(
  r'[\u3400-\u9fff]',
).allMatches(value).map((m) => m.group(0)!).toList();

List<String> pinyinSyllables(String value) => value
    .toLowerCase()
    .replaceAll('u:', 'ü')
    .replaceAll('v', 'ü')
    .split(RegExp(r"[^a-züāáǎàēéěèīíǐìōóǒòūúǔùǖǘǚǜ]+"))
    .where((item) => item.isNotEmpty)
    .toList(growable: false);
