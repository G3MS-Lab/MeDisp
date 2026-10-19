import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medisp/theme/medis_theme.dart';
import 'package:medisp/widgets/slide_to_confirm.dart';

void main() {
  testWidgets('confirmation can be completed using keyboard adjustments',
      (tester) async {
    var confirmed = 0;
    await tester.pumpWidget(MaterialApp(
        theme: MeDisTheme.light,
        home: Scaffold(
            body: Center(
                child: SizedBox(
                    width: 360,
                    child: SlideToConfirm(
                        label: 'สไลด์เพื่อบันทึก',
                        onConfirmed: () => confirmed++))))));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(tester.widget<Slider>(find.byType(Slider)).value, greaterThan(0));
    expect(confirmed, 0);
    for (var step = 0; step < 30 && confirmed == 0; step++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
    }
    expect(confirmed, 1);
    expect(tester.widget<Slider>(find.byType(Slider)).value, 0);
  });
}
