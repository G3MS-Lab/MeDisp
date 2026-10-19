@TestOn('browser')
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:medisp/data/local_image_store_web.dart';
import 'package:medisp/widgets/local_image_web.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web/web.dart' as web;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const store = LocalImageStore();
  const png =
      'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAEUlEQVR4nGP4z8DwH4QZYAwAR8oH+WdZbrcAAAAASUVORK5CYII=';

  test('large images survive a new store without consuming localStorage',
      () async {
    final bytes =
        Uint8List.fromList(List.generate(6 * 1024 * 1024, (i) => i % 251));
    final previousKeys = web.window.localStorage.length;
    final image = XFile.fromData(bytes, mimeType: 'image/jpeg');
    final path = await store.persist(image, category: 'drug_labels');
    expect(path, startsWith('medisp-image:'));
    expect(path.length, lessThan(100));
    expect(await const LocalImageStore().read(path), bytes);
    expect(await store.persist(image, category: 'allergies'), path);
    expect(web.window.localStorage.length, previousKeys);
  });

  test('migration shares one durable image reference across drug and slot',
      () async {
    const dataUrl = 'data:image/png;base64,$png';
    final drug = {'id': '1', 'label_image_path': dataUrl};
    SharedPreferences.setMockInitialValues({
      'medisp_user_drugs': jsonEncode([drug]),
      'dispenser_slots_user': jsonEncode([
        {'drug': drug, 'remaining': 10}
      ]),
    });
    await store.migrateLegacyImages();
    final preferences = await SharedPreferences.getInstance();
    final drugs =
        jsonDecode(preferences.getString('medisp_user_drugs')!) as List;
    final slots =
        jsonDecode(preferences.getString('dispenser_slots_user')!) as List;
    final path = drugs.single['label_image_path'] as String;
    expect(path, startsWith('medisp-image:'));
    expect(slots.single['drug']['label_image_path'], path);
    expect(await const LocalImageStore().read(path), base64Decode(png));
    expect(await store.read(dataUrl), base64Decode(png));
    await store.migrateLegacyImages();
    expect(
        preferences.getString('medisp_user_drugs'), isNot(contains('base64')));
  });

  testWidgets('renders an IndexedDB image and handles a missing image',
      (tester) async {
    // IndexedDB events run outside Flutter's fake clock. Pump between events
    // so both opening the database and reading the image can finish.
    Future<void> waitFor(Finder finder) async {
      for (var attempt = 0;
          attempt < 50 && finder.evaluate().isEmpty;
          attempt++) {
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        await tester.pump();
      }
    }

    final path = (await tester.runAsync(() => store
        .persist(XFile.fromData(base64Decode(png)), category: 'drug_labels')))!;
    await tester
        .pumpWidget(MaterialApp(home: localImage(path, width: 40, height: 40)));
    await waitFor(find.byType(Image));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(MaterialApp(
        home: localImage('medisp-image:missing',
            errorBuilder: (_, error, stack) => const Text('missing image'))));
    await waitFor(find.text('missing image'));
    await tester.pumpAndSettle();
    expect(find.text('missing image'), findsOneWidget);
  });
}
