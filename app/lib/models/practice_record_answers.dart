import 'practice.dart';

/// Keep interior empty cells so OCR results remain aligned with the writing grid.
List<String> trimTrailingEmptyOcrResults(List<String> results) {
  var length = results.length;
  while (length > 0 && results[length - 1].isEmpty) {
    length--;
  }
  return results.sublist(0, length);
}

/// Text shown to the student for a given practice direction.
String promptForPracticeDirection(
  PracticeQuestion question,
  PracticeDirection direction,
) => switch (direction) {
  PracticeDirection.writeHanzi ||
  PracticeDirection.listenWriteHanzi => question.prompt,
  PracticeDirection.writePinyin ||
  PracticeDirection.readAloud => question.answer,
};

/// Expected response is the text the student is asked to produce.
String expectedAnswerForPracticeDirection(
  PracticeQuestion question,
  PracticeDirection direction,
) => switch (direction) {
  PracticeDirection.writePinyin => question.prompt,
  PracticeDirection.writeHanzi ||
  PracticeDirection.listenWriteHanzi ||
  PracticeDirection.readAloud => question.answer,
};
