import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> slideControl(WidgetTester tester, Key key,
    {double fraction = 1}) async {
  final target = find.byKey(key);
  final scope = find.byType(AlertDialog).evaluate().isNotEmpty
      ? find.byType(AlertDialog)
      : find.byType(BottomSheet).evaluate().isNotEmpty
          ? find.byType(BottomSheet)
          : find.byType(Scaffold).last;
  final scroll = find.descendant(
      of: scope,
      matching: find.byWidgetPredicate((widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down));
  if (scroll.evaluate().isNotEmpty) {
    await tester.scrollUntilVisible(target, 300, scrollable: scroll.first);
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  final rect = tester.getRect(target);
  await tester.dragFrom(
      rect.centerLeft + const Offset(56, 0), Offset(rect.width * fraction, 0));
  await tester.pumpAndSettle();
}
