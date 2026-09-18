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
import 'package:zh_textbook/models/practice.dart';
import 'package:zh_textbook/models/engagement_event.dart';
import 'package:zh_textbook/models/textbook.dart';
import 'package:zh_textbook/screens/mode_page.dart';
import 'package:zh_textbook/screens/pet_home_page.dart';
import 'package:zh_textbook/screens/practice_page.dart';
import 'package:zh_textbook/services/numeric_pinyin.dart';
import 'package:zh_textbook/services/engagement_events.dart';
import 'package:zh_textbook/services/practice_progress.dart';
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

  testWidgets('模式页显示错题专项入口和当前错题数', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final source = File(
      '../json_reviewed/zh-lang-grade2b-textbook-struct.json',
    ).readAsStringSync();
    final textbook = Textbook.fromJsonString(source);
    final question = PracticeCatalog.fromTextbook(textbook).questions.first;
    final store = await PracticeProgressStore.open(
      const TextbookSelection(grade: 2, semester: Semester.second).fileName,
    );
    await store.record(
      question.attemptId(PracticeDirection.writeHanzi),
      correct: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ModePage(
          selection: const TextbookSelection(
            grade: 2,
            semester: Semester.second,
          ),
          textbook: textbook,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('错题专项'), findsOneWidget);
    expect(find.textContaining('1 道当前错题'), findsOneWidget);
    expect(find.byKey(const ValueKey('pet-growth-card')), findsOneWidget);
    expect(find.textContaining('成长值'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('pet-practice-invitation')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('pet-practice-invitation')));
    await tester.pumpAndSettle();
    expect(find.text('宠物三题陪练'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('pet-practice-companion')),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 10));
    expect(find.textContaining('慢慢想'), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    final events = (await EngagementEventStore.open()).events;
    expect(
      events.where(
        (event) => event.type == EngagementEventType.invitationPresented,
      ),
      hasLength(1),
    );
    expect(
      events.where(
        (event) => event.type == EngagementEventType.quickPracticeStarted,
      ),
      hasLength(1),
    );
    expect(
      events.where(
        (event) => event.type == EngagementEventType.quickPracticeExited,
      ),
      hasLength(1),
    );
    expect(
      events.where(
        (event) => event.type == EngagementEventType.goalPracticeStarted,
      ),
      isEmpty,
    );
  });

  testWidgets('模式页的目标入口只记录目标启动', (tester) async {
    final source = File(
      '../json_reviewed/zh-lang-grade2b-textbook-struct.json',
    ).readAsStringSync();
    final textbook = Textbook.fromJsonString(source);
    const selection = TextbookSelection(grade: 2, semester: Semester.second);

    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      MaterialApp(
        home: ModePage(selection: selection, textbook: textbook),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pet-learning-goal')));
    await tester.pumpAndSettle();
    expect(find.text('宠物三题陪练'), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    final goalStarts = (await EngagementEventStore.open()).events.where(
      (event) => event.type == EngagementEventType.goalPracticeStarted,
    );
    expect(goalStarts, hasLength(1));
    expect(goalStarts.single.context.surface, EngagementSurface.modePage);
    expect(goalStarts.single.context.launchSource, EngagementLaunchSource.goal);
  });

  testWidgets('宠物之家的目标入口记录目标启动', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final source = File(
      '../json_reviewed/zh-lang-grade2b-textbook-struct.json',
    ).readAsStringSync();
    final textbook = Textbook.fromJsonString(source);
    const selection = TextbookSelection(grade: 2, semester: Semester.second);
    await tester.pumpWidget(
      MaterialApp(
        home: PetHomePage(selection: selection, textbook: textbook),
      ),
    );
    await tester.pumpAndSettle();
    final homeGoal = find.byKey(const ValueKey('pet-home-learning-goal'));
    await tester.scrollUntilVisible(
      homeGoal,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(homeGoal, findsOneWidget);
    await tester.tap(homeGoal);
    await tester.pumpAndSettle();
    expect(find.text('宠物三题陪练'), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    final goalStarts = (await EngagementEventStore.open()).events.where(
      (event) => event.type == EngagementEventType.goalPracticeStarted,
    );
    expect(goalStarts, hasLength(1));
    expect(goalStarts.single.context.surface, EngagementSurface.petHome);
    expect(goalStarts.single.context.launchSource, EngagementLaunchSource.goal);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('目标不足三题时说明原因并进入对应课文普通练习', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final textbook = _sparseTextbook();
    const selection = TextbookSelection(grade: 2, semester: Semester.second);
    await tester.pumpWidget(
      MaterialApp(
        home: ModePage(selection: selection, textbook: textbook),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('进入本课练习'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pet-learning-goal')));
    await tester.pump();
    expect(find.textContaining('不足 3 题'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('语文基础练习'), findsOneWidget);
    expect(find.text('宠物三题陪练'), findsNothing);
  });

  testWidgets('练习页可以从错题数量快捷进入专项模式', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final source = File(
      '../json_reviewed/zh-lang-grade2b-textbook-struct.json',
    ).readAsStringSync();
    final textbook = Textbook.fromJsonString(source);
    final question = PracticeCatalog.fromTextbook(textbook).questions.first;
    final store = await PracticeProgressStore.open(
      const TextbookSelection(grade: 2, semester: Semester.second).fileName,
    );
    await store.record(
      question.attemptId(PracticeDirection.writeHanzi),
      correct: false,
    );

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
    await tester.tap(find.text('当前错题 1'));
    await tester.pumpAndSettle();

    expect(find.text('整本教材错题专项'), findsOneWidget);
    expect(find.text('返回综合练习'), findsOneWidget);
  });
}

Textbook _sparseTextbook() => Textbook.fromJson({
  'schema_version': 1,
  'index': [
    {
      'id': 'unit-1',
      'name': '第一单元',
      'chapters': [
        {'id': 'lesson-sparse', 'name': '第一课', 'children': []},
      ],
    },
  ],
  'contents': [
    {
      'id': 'unit-1',
      'name': '第一单元',
      'chapters': [
        {'id': 'lesson-sparse', 'name': '第一课', 'text': [], 'children': []},
      ],
    },
    {
      'id': 'appendix',
      'name': '附录',
      'chapters': [
        {
          'id': 'appendix-recognition',
          'name': '识字表',
          'children': [],
          'text': [
            {
              'id': 'spring',
              'zh': '春',
              'pinyin': 'chūn',
              'introduced_at': {'chapter_id': 'lesson-sparse'},
              'refs': [],
            },
          ],
        },
      ],
    },
  ],
});
