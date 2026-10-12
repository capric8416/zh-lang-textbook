import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zh_textbook/pet_interactions_app.dart';

void main() {
  testWidgets('互动应用按顺序解锁并支持返回上一项', (tester) async {
    await tester.pumpWidget(const PetInteractionsApp());

    expect(find.text('挥爪邀请'), findsOneWidget);
    expect(find.text('已解锁 1 / 14'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('pet-live-animation-invite')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('pet-interaction-previous')),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const ValueKey('pet-interaction-next')));
    await tester.pump();
    expect(find.text('安静思考'), findsOneWidget);
    expect(find.text('已解锁 2 / 14'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('pet-live-animation-think')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('pet-interaction-previous')));
    await tester.pump();
    expect(find.text('挥爪邀请'), findsOneWidget);
    expect(find.text('已解锁 1 / 14'), findsOneWidget);
  });

  testWidgets('互动应用会在最后一项停下', (tester) async {
    await tester.pumpWidget(const PetInteractionsApp());
    final next = find.byKey(const ValueKey('pet-interaction-next'));

    for (var index = 1; index < 14; index++) {
      await tester.tap(next);
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(find.text('单元礼花'), findsOneWidget);
    expect(find.text('已解锁 14 / 14'), findsOneWidget);
    expect(tester.widget<FilledButton>(next).onPressed, isNull);
  });
}
