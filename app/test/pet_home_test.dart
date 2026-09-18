import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zh_textbook/models/pet.dart';
import 'package:zh_textbook/models/engagement_event.dart';
import 'package:zh_textbook/models/textbook.dart';
import 'package:zh_textbook/screens/pet_home_page.dart';
import 'package:zh_textbook/screens/practice_page.dart';
import 'package:zh_textbook/services/pet_growth.dart';
import 'package:zh_textbook/services/engagement_events.dart';
import 'package:zh_textbook/services/textbook_repository.dart';

void main() {
  testWidgets('宠物之家显示互动、品种和装饰入口', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: PetHomePage()));
    await tester.pumpAndSettle();

    expect(find.text('宠物之家'), findsOneWidget);
    expect(find.byKey(const ValueKey('pet-room-living-room')), findsOneWidget);
    expect(find.byKey(const ValueKey('furniture-pet-bed')), findsNothing);
    await tester.scrollUntilVisible(find.text('学习装饰'), 300);
    expect(find.text('摸摸头'), findsOneWidget);
    expect(find.text('打个招呼'), findsOneWidget);
    expect(find.text('摇尾巴'), findsOneWidget);
    expect(find.text('选择伙伴'), findsOneWidget);
    expect(find.text('学习装饰'), findsOneWidget);
    expect(find.text('小狗'), findsOneWidget);
  });

  testWidgets('互动只更新本地反馈，不改变成长值', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: PetHomePage()));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -420));
    await tester.pumpAndSettle();
    expect(find.text('成长值 0 · 大阶段 0'), findsOneWidget);
    await tester.tap(find.text('摸摸头'));
    await tester.pump();
    expect(find.text('摸摸头，真棒！'), findsOneWidget);
    expect(find.text('成长值 0 · 大阶段 0'), findsOneWidget);
  });

  testWidgets('切换房间后自动显示该房间已解锁家具', (tester) async {
    SharedPreferences.setMockInitialValues({
      'pet_growth_profile': jsonEncode({
        'version': 3,
        'profile': const PetProfile(
          majorStage: 2,
          unlockedFurniture: {
            'pet-bed',
            'soft-rug',
            'study-desk',
            'desk-lamp',
            'shade-tree',
          },
        ).toJson(),
      }),
    });
    await tester.pumpWidget(const MaterialApp(home: PetHomePage()));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('furniture-pet-bed')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('room-study-room')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pet-room-study-room')), findsOneWidget);
    expect(find.byKey(const ValueKey('furniture-study-desk')), findsOneWidget);
    expect(find.byKey(const ValueKey('furniture-desk-lamp')), findsOneWidget);
    expect(find.byIcon(Icons.play_circle_fill), findsNWidgets(2));
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.textContaining('小书柜（大阶段3解锁）'), findsOneWidget);

    final stored = await SharedPreferences.getInstance();
    final raw = stored.getString('pet_growth_profile');
    expect(raw, contains('study-room'));
  });

  testWidgets('宠物可以改名并持久化', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: PetHomePage()));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('rename-pet')),
      250,
    );
    await tester.tap(find.byKey(const ValueKey('rename-pet')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('pet-name-field')), '豆豆');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('豆豆'), findsOneWidget);
    final reopened = await PetGrowthStore.open();
    expect(reopened.profile.name, '豆豆');
  });

  testWidgets('学习家具进入当前教材三题陪练并可提前返回', (tester) async {
    SharedPreferences.setMockInitialValues({
      'pet_growth_profile': jsonEncode({
        'version': 3,
        'profile': const PetProfile(
          majorStage: 4,
          unlockedFurniture: {
            'pet-bed',
            'soft-rug',
            'toy-box',
            'study-desk',
            'desk-lamp',
            'bookcase',
            'shade-tree',
            'flower-pot',
            'garden-swing',
          },
        ).toJson(),
      }),
    });
    final source = File(
      '../json_reviewed/zh-lang-grade2b-textbook-struct.json',
    ).readAsStringSync();
    final textbook = Textbook.fromJsonString(source);

    await tester.pumpWidget(
      MaterialApp(
        home: PetHomePage(
          selection: const TextbookSelection(
            grade: 2,
            semester: Semester.second,
          ),
          textbook: textbook,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('room-study-room')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('furniture-desk-lamp')));
    await tester.pumpAndSettle();

    expect(find.text('宠物三题陪练'), findsOneWidget);
    expect(find.text('三题汉字拼音'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('quick-practice-progress')),
      findsOneWidget,
    );
    expect(find.text('1/3'), findsOneWidget);

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('宠物之家'), findsOneWidget);
    expect(find.text('三题陪练完成，真棒！'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('furniture-desk-lamp')));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(PracticePage))).pop(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('pet-quick-reaction')), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.drag(find.byType(ListView), const Offset(0, -420));
    await tester.pumpAndSettle();
    expect(find.text('三题陪练完成，真棒！'), findsOneWidget);
  });

  testWidgets('三题陪练进度组件显示首题和末题', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              QuickPracticeProgressIndicator(current: 1, total: 3),
              QuickPracticeProgressIndicator(current: 3, total: 3),
            ],
          ),
        ),
      ),
    );

    expect(find.text('1/3'), findsOneWidget);
    expect(find.text('3/3'), findsOneWidget);
  });

  testWidgets('激活家具显示语义状态并确认一次性解锁提示', (tester) async {
    SharedPreferences.setMockInitialValues({
      'pet_growth_profile': jsonEncode({
        'version': 5,
        'profile': const PetProfile(
          selectedRoom: 'study-room',
          unlockedFurniture: {'study-desk', 'desk-lamp'},
          furnitureStates: {
            'study-desk': FurnitureVisualState.ready,
            'desk-lamp': FurnitureVisualState.active,
          },
          pendingFurnitureReveals: {'desk-lamp'},
        ).toJson(),
      }),
    });
    await tester.pumpWidget(const MaterialApp(home: PetHomePage()));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('furniture-active-desk-lamp')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    final reopened = await PetGrowthStore.open();
    expect(reopened.profile.pendingFurnitureReveals, isEmpty);
  });

  testWidgets('提前退出三题记录开始和退出但不记录完成', (tester) async {
    SharedPreferences.setMockInitialValues({
      'pet_growth_profile': jsonEncode({
        'version': 5,
        'profile': const PetProfile(
          majorStage: 1,
          selectedRoom: 'study-room',
          unlockedFurniture: {'study-desk', 'desk-lamp'},
        ).toJson(),
      }),
    });
    final textbook = Textbook.fromJsonString(
      File(
        '../json_reviewed/zh-lang-grade2b-textbook-struct.json',
      ).readAsStringSync(),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PetHomePage(
          selection: const TextbookSelection(
            grade: 2,
            semester: Semester.second,
          ),
          textbook: textbook,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('room-study-room')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('furniture-desk-lamp')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();

    final events = (await EngagementEventStore.open()).events;
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
        (event) => event.type == EngagementEventType.quickPracticeCompleted,
      ),
      isEmpty,
    );
  });
}
