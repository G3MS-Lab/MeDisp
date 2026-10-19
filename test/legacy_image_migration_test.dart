import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:medisp/data/legacy_image_migration.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const image = 'data:image/png;base64,AQID';
  final drug = {'id': 'drug-1', 'name': 'Medicine', 'label_image_path': image};

  test('migrates drug, nested slot and allergy images across existing users',
      () async {
    final records = {
      'medisp_user1_drugs': jsonEncode([drug]),
      'dispenser_slots_user1': jsonEncode([
        {'number': 1, 'remaining': 10, 'drug': drug}
      ]),
      'medisp_user2_allergies': jsonEncode([
        {'description': 'rash', 'image_path': image}
      ]),
      'unrelated_drugs': jsonEncode([drug]),
      'medisp_user1_profile': jsonEncode({'name': image}),
    };
    SharedPreferences.setMockInitialValues(records);
    var calls = 0;
    await migrateLegacyImagePreferences((dataUrl) async {
      expect(dataUrl, image);
      calls++;
      return 'medisp-image:stored';
    });
    final preferences = await SharedPreferences.getInstance();
    final drugs =
        jsonDecode(preferences.getString('medisp_user1_drugs')!) as List;
    expect(drugs.single, {...drug, 'label_image_path': 'medisp-image:stored'});
    final slots =
        jsonDecode(preferences.getString('dispenser_slots_user1')!) as List;
    expect(slots.single['remaining'], 10);
    expect(slots.single['drug']['label_image_path'], 'medisp-image:stored');
    final allergies =
        jsonDecode(preferences.getString('medisp_user2_allergies')!) as List;
    expect(allergies.single['image_path'], 'medisp-image:stored');
    expect(
        preferences.getString('unrelated_drugs'), records['unrelated_drugs']);
    expect(preferences.getString('medisp_user1_profile'),
        records['medisp_user1_profile']);
    expect(calls, 3);
    await migrateLegacyImagePreferences(
        (_) async => throw StateError('already migrated'));
    expect(calls, 3);
  });

  test('failed image write preserves the entire collection and can be retried',
      () async {
    final original = jsonEncode([
      drug,
      {...drug, 'id': 'drug-2'}
    ]);
    SharedPreferences.setMockInitialValues({'medisp_user_drugs': original});
    var calls = 0;
    await migrateLegacyImagePreferences((_) async {
      if (++calls == 2) throw StateError('storage unavailable');
      return 'medisp-image:stored';
    });
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('medisp_user_drugs'), original);
    await migrateLegacyImagePreferences((_) async => 'medisp-image:stored');
    expect(preferences.getString('medisp_user_drugs'), isNot(contains(image)));
    expect(
        (jsonDecode(preferences.getString('medisp_user_drugs')!) as List)
            .length,
        2);
  });
}
