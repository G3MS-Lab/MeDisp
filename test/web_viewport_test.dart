import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medisp/widgets/medis_web_viewport.dart';

void main() {
  for (final window in [
    const Size(1440, 900),
    const Size(390, 720),
    const Size(1920, 1200)
  ]) {
    testWidgets('web keeps iPhone proportions within $window', (tester) async {
      tester.view.physicalSize = window;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Size? logicalSize;
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MeDisWebViewport(child: Builder(
          builder: (context) {
            logicalSize = MediaQuery.sizeOf(context);
            return const ColoredBox(key: Key('screen'), color: Colors.white);
          },
        )),
        home: const SizedBox.shrink(),
      ));
      final bounds = tester.getRect(find.byKey(const Key('screen')));
      expect(logicalSize, const Size(440, 956));
      expect(bounds.width / bounds.height, closeTo(1320 / 2868, .00001));
      expect(bounds.width, lessThanOrEqualTo(window.width));
      expect(bounds.height, lessThanOrEqualTo(window.height));
      expect(bounds.center.dx, closeTo(window.width / 2, .01));
      expect(bounds.center.dy, closeTo(window.height / 2, .01));
      expect(tester.takeException(), isNull);
    });
  }
}
