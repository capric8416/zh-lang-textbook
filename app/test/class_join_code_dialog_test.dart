import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zh_textbook/widgets/class_join_code_dialog.dart';

void main() {
  testWidgets('班级二维码在深色主题和矮窗口中正常显示', (tester) async {
    tester.view.physicalSize = const Size(800, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const ClassJoinCodeDialog(
                  className: '六年级一班',
                  code: 'abcd1234',
                ),
              ),
              child: const Text('显示二维码'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('显示二维码'));
    await tester.pumpAndSettle();

    expect(find.text('六年级一班 入班码'), findsOneWidget);
    expect(find.bySemanticsLabel('班级入班二维码'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
