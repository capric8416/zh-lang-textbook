import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zh_textbook/models/practice.dart';
import 'package:zh_textbook/models/textbook.dart';
import 'package:zh_textbook/services/textbook_repository.dart';

void main() {
  test('年级和学期生成正确的教材资源名', () {
    const selection = TextbookSelection(grade: 2, semester: Semester.second);

    expect(selection.fileName, 'zh-lang-grade2b-textbook-struct.json');
    expect(
      selection.assetPath,
      'assets/json_reviewed/zh-lang-grade2b-textbook-struct.json',
    );
  });

  test('二年级下册结构和倒查标记可以解析', () {
    final source = File(
      '../json_reviewed/zh-lang-grade2b-textbook-struct.json',
    ).readAsStringSync();
    final textbook = Textbook.fromJsonString(source);

    expect(textbook.schemaVersion, 2);
    expect(textbook.index, hasLength(9));
    expect(textbook.chaptersById, hasLength(40));
    expect(textbook.chapter('u01-reading-01')?.name, '古诗二首');
    expect(
      textbook.highlights.forField('u01-reading-01-poem-01', 'title'),
      isNotEmpty,
    );
    expect(
      textbook.highlights.forSegment('u01-reading-01-poem-01-line-01'),
      isNotEmpty,
    );
  });

  test('练习题由附录引用、词表和背诵诗词生成', () {
    final source = File(
      '../json_reviewed/zh-lang-grade2b-textbook-struct.json',
    ).readAsStringSync();
    final textbook = Textbook.fromJsonString(source);
    final catalog = PracticeCatalog.fromTextbook(textbook);
    final chapterIds = textbook.index
        .where((unit) => unit.id != 'appendix')
        .expand((unit) => unit.chapters)
        .map((chapter) => chapter.id)
        .toSet();

    expect(catalog.questions.length, greaterThan(900));
    expect(catalog.questions.any((item) => item.category == '字'), isTrue);
    expect(catalog.questions.any((item) => item.category == '词'), isTrue);
    expect(catalog.questions.any((item) => item.category == '引用句子'), isTrue);
    expect(catalog.questions.any((item) => item.category == '诗词'), isTrue);
    expect(
      catalog.questions.every(
        (question) => chapterIds.contains(question.chapterId),
      ),
      isTrue,
    );
  });

  test('练习题可按课文目录归类', () {
    final source = File(
      '../json_reviewed/zh-lang-grade2b-textbook-struct.json',
    ).readAsStringSync();
    final catalog = PracticeCatalog.fromTextbook(
      Textbook.fromJsonString(source),
    );
    final questions = catalog.forChapter('u01-reading-01');

    expect(questions, isNotEmpty);
    expect(
      questions.every((question) => question.chapterId == 'u01-reading-01'),
      isTrue,
    );
    expect(questions.any((question) => question.category == '诗词'), isTrue);
  });
}
