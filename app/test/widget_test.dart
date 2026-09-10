// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zh_textbook/main.dart';
import 'package:zh_textbook/models/textbook.dart';
import 'package:zh_textbook/screens/practice_page.dart';
import 'package:zh_textbook/services/numeric_pinyin.dart';
import 'package:zh_textbook/services/textbook_repository.dart';

void main() {
  test('教材拼音在运行时转换为 Piper 数字声调', () {
    final source = File(
      '../json_reviewed/zh-lang-grade2b-textbook-struct.json',
    ).readAsStringSync();
    final textbook = Textbook.fromJsonString(source);
    final line = textbook.segment('u01-reading-01-poem-01-line-04');

    expect(line, isNotNull);
    expect(
      toNumericPinyin(line!.pinyin),
      'er4 yue4 chun1 feng1 si4 jian3 dao1',
    );
  });

  testWidgets('首页显示教材选择', (WidgetTester tester) async {
    await tester.pumpWidget(const ZhTextbookApp());

    expect(find.text('语文基础巩固与练习'), findsOneWidget);
    expect(find.text('2年级'), findsOneWidget);
    expect(find.text('下学期'), findsOneWidget);
    expect(find.text('进入教材'), findsOneWidget);
  });

  testWidgets('练习页可以加载题库并显示题目', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final source = File(
      '../json_reviewed/zh-lang-grade2b-textbook-struct.json',
    ).readAsStringSync();
    final textbook = Textbook.fromJsonString(source);

    await tester.pumpWidget(
      MaterialApp(
        home: PracticePage(
          selection: const TextbookSelection(
            grade: 2,
            semester: Semester.second,
          ),
          textbook: textbook,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('打开目录'));
    await tester.pumpAndSettle();

    expect(find.text('练习目录'), findsOneWidget);
    expect(
      find.textContaining(RegExp(r'看拼音写汉字|看汉字写拼音|听音写汉字|朗读检查')),
      findsOneWidget,
    );
    expect(find.text('下一题'), findsNothing);
    expect(find.textContaining(RegExp(r'批改|开始朗读')), findsOneWidget);
  });
}
