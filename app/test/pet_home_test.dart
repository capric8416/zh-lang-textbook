import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zh_textbook/models/pet.dart';
import 'package:zh_textbook/screens/pet_home_page.dart';

void main() {
  testWidgets('宠物之家显示互动、品种和装饰入口', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: PetHomePage()));
    await tester.pumpAndSettle();

    expect(find.text('宠物之家'), findsOneWidget);
    expect(find.byKey(const ValueKey('pet-room-living-room')), findsOneWidget);
    expect(find.byKey(const ValueKey('furniture-pet-bed')), findsNothing);
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
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
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.textContaining('小书柜（大阶段3解锁）'), findsOneWidget);

    final stored = await SharedPreferences.getInstance();
    final raw = stored.getString('pet_growth_profile');
    expect(raw, contains('study-room'));
  });
}
