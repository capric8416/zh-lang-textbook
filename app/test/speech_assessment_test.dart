import 'package:flutter_test/flutter_test.dart';
import 'package:zh_textbook/models/speech_assessment.dart';

void main() {
  test('朗读结果按带声调拼音逐音节比较', () {
    final result = SpeechAssessment.compare(
      expectedPinyin: 'chūn fēng yòu lǜ jiāng nán àn',
      recognizedText: '春风又绿江南岸',
    );

    expect(result.recognizedPinyin, 'chūn fēng yòu lǜ jiāng nán àn');
    expect(result.matchedSyllables, 7);
    expect(result.automaticallyCorrect, isTrue);
  });

  test('同音不同字允许在人工复核前按拼音匹配', () {
    final result = SpeechAssessment.compare(
      expectedPinyin: 'hé',
      recognizedText: '河',
    );

    expect(result.automaticallyCorrect, isTrue);
  });

  test('漏读会被标记为需要复核', () {
    final result = SpeechAssessment.compare(
      expectedPinyin: 'chūn fēng',
      recognizedText: '春',
    );

    expect(result.matchRate, 0.5);
    expect(result.automaticallyCorrect, isFalse);
  });

  test('插入语气词不会导致后续音节全部错位', () {
    final result = SpeechAssessment.compare(
      expectedPinyin: 'chūn fēng yòu lǜ',
      recognizedText: '春风啊又绿',
    );

    expect(result.matchedSyllables, 4);
    expect(result.automaticallyCorrect, isFalse);
  });
}
