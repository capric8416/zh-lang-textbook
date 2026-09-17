import 'package:flutter_test/flutter_test.dart';
import 'package:zh_textbook/models/speech_assessment.dart';

void main() {
  test('朗读结果按带声调拼音逐音节比较', () {
    final result = SpeechAssessment.compare(
      expectedText: '春风又绿江南岸',
      expectedPinyin: 'chūn fēng yòu lǜ jiāng nán àn',
      recognizedText: '春风又绿江南岸',
    );

    expect(result.recognizedPinyin, 'chūn fēng yòu lǜ jiāng nán àn');
    expect(result.matchedSyllables, 7);
    expect(result.automaticallyCorrect, isTrue);
  });

  test('同音不同字允许在人工复核前按拼音匹配', () {
    final result = SpeechAssessment.compare(
      expectedText: '河',
      expectedPinyin: 'hé',
      recognizedText: '河',
    );

    expect(result.automaticallyCorrect, isTrue);
  });

  test('漏读会被标记为需要复核', () {
    final result = SpeechAssessment.compare(
      expectedText: '春风',
      expectedPinyin: 'chūn fēng',
      recognizedText: '春',
    );

    expect(result.matchRate, 0.5);
    expect(result.automaticallyCorrect, isFalse);
  });

  test('插入语气词不会导致后续音节全部错位', () {
    final result = SpeechAssessment.compare(
      expectedText: '春风又绿',
      expectedPinyin: 'chūn fēng yòu lǜ',
      recognizedText: '春风啊又绿',
    );

    expect(result.matchedSyllables, 4);
    expect(result.automaticallyCorrect, isFalse);
  });

  test('汉字相同但多音字拼音不同，按汉字匹配并修正显示拼音', () {
    final result = SpeechAssessment.compare(
      expectedText: '长',
      expectedPinyin: 'zhǎng',
      recognizedText: '长',
    );

    expect(result.matchedSyllables, 1);
    expect(result.automaticallyCorrect, isTrue);
    expect(result.recognizedText, '长');
    expect(result.recognizedPinyin, 'zhǎng');
  });

  test('拼音相同但汉字不同，按拼音匹配并修正显示汉字', () {
    final result = SpeechAssessment.compare(
      expectedText: '河',
      expectedPinyin: 'hé',
      recognizedText: '何',
    );

    expect(result.matchedSyllables, 1);
    expect(result.automaticallyCorrect, isTrue);
    expect(result.recognizedText, '河');
    expect(result.recognizedPinyin, 'hé');
  });
}
