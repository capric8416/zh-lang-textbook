// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
import 'package:zh_textbook/services/study_state_sync.dart';
import 'package:zh_textbook/services/textbook_repository.dart';

void main() {
  setUp(() {
    StudyStateSync.unbind();
    FlutterSecureStorage.setMockInitialValues({
      'account_session_token': 'widget-test-token',
      'account_session_account_id': 'widget-test-account',
    });
  });

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

  testWidgets('未登录时先显示登录页', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await tester.pumpWidget(const ZhTextbookApp());
    await _pumpUntilFound(tester, find.text('登录账号'));

    expect(find.text('需要连接账号服务并登录后才能进入学习。'), findsOneWidget);
    expect(find.text('进入教材'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('首页恢复上次进入教材时的年级和学期', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'textbook_selection_v1_widget-test-account':
          '{"grade":3,"semester":"a","dirty":false}',
    });
    await tester.pumpWidget(const ZhTextbookApp());
    await _pumpUntilFound(
      tester,
      find.byType(DropdownButtonFormField<int>),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      tester
          .widget<DropdownButtonFormField<int>>(
            find.byType(DropdownButtonFormField<int>),
          )
          .initialValue,
      3,
    );
    expect(
      tester
          .widget<SegmentedButton<Semester>>(
            find.byType(SegmentedButton<Semester>),
          )
          .selected,
      {Semester.first},
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
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
    await _pumpUntilFound(tester, find.byTooltip('打开目录'));

    await tester.tap(find.byTooltip('打开目录'));
    await _pumpUntilFound(tester, find.text('练习目录'));

    expect(find.text('练习目录'), findsOneWidget);
    expect(
      find.textContaining(RegExp(r'看拼音写汉字|看汉字写拼音|听音写汉字|朗读检查')),
      findsOneWidget,
    );
    expect(find.text('下一题'), findsNothing);
    expect(find.textContaining(RegExp(r'批改|开始朗读')), findsOneWidget);
  });

  testWidgets('模式页显示再练一练入口和当前错题数', (WidgetTester tester) async {
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
    await _pumpUntilFound(tester, find.textContaining('1 道题目再练一练'));

    expect(find.text('再练一练'), findsOneWidget);
    expect(find.textContaining('1 道题目再练一练'), findsOneWidget);
    expect(find.byKey(const ValueKey('pet-growth-card')), findsOneWidget);
    expect(find.textContaining('成长值'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('pet-practice-invitation')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('pet-practice-invitation')));
    await _pumpUntilFound(tester, find.text('宠物三题陪练'));
    expect(find.text('宠物三题陪练'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('pet-practice-companion')),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 10));
    expect(find.textContaining('陪你慢慢想'), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    await tester.pump(const Duration(seconds: 1));
    final events = (await EngagementEventStore.open()).events;
    expect(
      events.where(
        (event) => event.type == EngagementEventType.invitationPresented,
      ),
      hasLength(2),
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
    await _pumpUntilFound(
      tester,
      find.byKey(const ValueKey('pet-learning-goal')),
    );
    await tester.tap(find.byKey(const ValueKey('pet-learning-goal')));
    await _pumpUntilFound(tester, find.text('宠物三题陪练'));
    expect(find.text('宠物三题陪练'), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    await tester.pump(const Duration(seconds: 1));
    final goalStarts = (await EngagementEventStore.open()).events.where(
      (event) => event.type == EngagementEventType.goalPracticeStarted,
    );
    expect(goalStarts, hasLength(1));
    expect(goalStarts.single.context.surface, EngagementSurface.modePage);
    expect(goalStarts.single.context.launchSource, EngagementLaunchSource.goal);
  });

  testWidgets('爪爪星球的目标入口记录目标启动', (tester) async {
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
    await _pumpUntilFound(tester, find.text('选择房间'));
    final homeGoal = find.byKey(const ValueKey('pet-home-learning-goal'));
    await tester.dragUntilVisible(
      homeGoal,
      find.byType(Scrollable).first,
      const Offset(0, -300),
    );
    expect(homeGoal, findsOneWidget);
    await tester.tap(homeGoal);
    await _pumpUntilFound(tester, find.text('宠物三题陪练'));
    expect(find.text('宠物三题陪练'), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    await tester.pump(const Duration(seconds: 1));
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
    await _pumpUntilFound(tester, find.textContaining('进入本课练习'));

    expect(find.textContaining('进入本课练习'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pet-learning-goal')));
    await tester.pump();
    expect(find.textContaining('不足 3 题'), findsOneWidget);
    await _pumpUntilFound(tester, find.text('语文基础练习'));
    await tester.pump(const Duration(seconds: 1));
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
    await _pumpUntilFound(tester, find.text('待巩固 1'));
    await tester.tap(find.text('待巩固 1'));
    await _pumpUntilFound(tester, find.text('整本教材 · 再练一练'));

    expect(find.text('整本教材 · 再练一练'), findsOneWidget);
    expect(find.text('返回综合练习'), findsOneWidget);
  });
}

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 100,
}) async {
  for (var pump = 0; pump < maxPumps; pump++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (finder.evaluate().isNotEmpty) return;
  }
  final visibleText = find
      .byType(Text)
      .evaluate()
      .map((element) => (element.widget as Text).data)
      .whereType<String>()
      .take(12)
      .join(' | ');
  throw TestFailure(
    '等待控件超时：${finder.describeMatch(Plurality.one)}；当前文字：$visibleText',
  );
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
