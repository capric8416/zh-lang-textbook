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
import 'package:zh_textbook/services/textbook_repository.dart';

void main() {
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
    expect(find.text('书写区'), findsOneWidget);
    expect(find.text('下一题'), findsNothing);
    expect(find.text('批改'), findsOneWidget);
  });
}
