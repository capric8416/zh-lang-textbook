import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zh_textbook/screens/pet_home_page.dart';

void main() {
  testWidgets('宠物之家显示互动、品种和装饰入口', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: PetHomePage()));
    await tester.pumpAndSettle();

    expect(find.text('宠物之家'), findsOneWidget);
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

    expect(find.text('成长值 0 · 大阶段 0'), findsOneWidget);
    await tester.tap(find.text('摸摸头'));
    await tester.pump();
    expect(find.text('摸摸头，真棒！'), findsOneWidget);
    expect(find.text('成长值 0 · 大阶段 0'), findsOneWidget);
  });
}
