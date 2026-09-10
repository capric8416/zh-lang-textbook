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
    required String expectedPinyin,
    required String recognizedText,
  }) {
    final expected = pinyinSyllables(expectedPinyin);
    final recognizedPinyin = PinyinHelper.getPinyinE(
      recognizedText,
      separator: ' ',
      defPinyin: '',
      format: PinyinFormat.WITH_TONE_MARK,
    );
    final recognized = pinyinSyllables(recognizedPinyin);
    final matched = _longestCommonSubsequence(expected, recognized);
    return SpeechAssessment(
      recognizedText: recognizedText,
      expectedPinyin: expected.join(' '),
      recognizedPinyin: recognized.join(' '),
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

int _longestCommonSubsequence(List<String> expected, List<String> actual) {
  var previous = List<int>.filled(actual.length + 1, 0);
  for (final expectedSyllable in expected) {
    final current = List<int>.filled(actual.length + 1, 0);
    for (var index = 0; index < actual.length; index++) {
      current[index + 1] = expectedSyllable == actual[index]
          ? previous[index] + 1
          : current[index] > previous[index + 1]
          ? current[index]
          : previous[index + 1];
    }
    previous = current;
  }
  return previous.last;
}

List<String> pinyinSyllables(String value) => value
    .toLowerCase()
    .replaceAll('u:', 'ü')
    .replaceAll('v', 'ü')
    .split(RegExp(r"[^a-züāáǎàēéěèīíǐìōóǒòūúǔùǖǘǚǜ]+"))
    .where((item) => item.isNotEmpty)
    .toList(growable: false);
