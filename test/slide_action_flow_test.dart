import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medisp/application/app_controller.dart';
import 'package:medisp/application/app_scope.dart';
import 'package:medisp/data/auth_repositories.dart';
import 'package:medisp/data/persistent_dispenser_repository.dart';
import 'package:medisp/data/persistent_medication_repository.dart';
import 'package:medisp/domain/models.dart';
import 'package:medisp/screens/daily_screen.dart';
import 'package:medisp/screens/dispenser_screen.dart';
import 'package:medisp/screens/profile_edit_screen.dart';
import 'package:medisp/screens/profile_screen.dart';
import 'package:medisp/screens/reminder_settings_screen.dart';
import 'package:medisp/theme/medis_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/slide_gesture.dart';

Future<AppController> fixture() async {
  SharedPreferences.setMockInitialValues({});
  final auth = OfflineAuthRepository(MemoryAuthStorage());
  await auth.initialize();
  await auth.register(
      name: 'Patient', email: 'slide@example.com', password: 'password');
  final controller = AppController(auth, PersistentDispenserRepository(auth),
      PersistentMedicationRepository(auth));
  await controller.initialize();
  await controller.toggleConnection();
  await controller.addDrugToSlot(
      const Drug(id: 'scheduled', name: 'Scheduled medicine', instructions: [
        DoseInstruction(meal: MealType.breakfast, quantity: 1)
      ]),
      1,
      7);
  await controller.addDrugToSlot(
      const Drug(
          id: 'prn',
          name: 'PRN medicine',
          isPrn: true,
          prnConfig: PrnConfig(
              symptom: 'Pain',
              quantity: 1,
              minIntervalHours: 4,
              maxDosesPerDay: 4)),
      2,
      8);
  return controller;
}

Future<AppController> mount(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(430, 956);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final controller = (await tester.runAsync(fixture))!;
  await tester.pumpWidget(AppScope(
      controller: controller,
      child: MaterialApp(
          theme: MeDisTheme.light,
          home: Builder(
              builder: (context) => Scaffold(
                  body: Center(
                      child: TextButton(
                          onPressed: () => Navigator.push(context,
                              MaterialPageRoute<void>(builder: (_) => screen)),
                          child: const Text('Open'))))))));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  return controller;
}

void main() {
  testWidgets('scheduled intake uses button tap and popup slide confirmation',
      (tester) async {
    final controller = await mount(tester, const Scaffold(body: DailyScreen()));
    const receive = Key('receive-meal-breakfast');
    const confirm = Key('confirm-intake-slider');
    await tester.tap(find.byKey(receive));
    await tester.pumpAndSettle();
    expect(find.text('ตรวจสอบยาก่อนทาน'), findsOneWidget);
    expect(find.text('Scheduled medicine'), findsWidgets);
    await tester.tap(find.text('ยังไม่ทาน'));
    await tester.pumpAndSettle();
    expect(controller.slots.first.remaining, 7);
    await tester.tap(find.byKey(receive));
    await tester.pumpAndSettle();
    await slideControl(tester, confirm, fraction: .4);
    expect(controller.intakeHistory, isEmpty);
    expect(controller.slots.first.remaining, 7);
    await slideControl(tester, confirm);
    expect(controller.intakeHistory, hasLength(1));
    expect(controller.slots.first.remaining, 6);
    expect(tester.widget<FilledButton>(find.byKey(receive)).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('PRN button respects the cooldown after one confirmed intake',
      (tester) async {
    final controller = await mount(tester, const Scaffold(body: DailyScreen()));
    await tester.tap(find.text('ตามอาการ'));
    await tester.pumpAndSettle();
    const receive = Key('receive-prn-2');
    await tester.tap(find.byKey(receive));
    await tester.pumpAndSettle();
    await slideControl(tester, const Key('confirm-intake-slider'),
        fraction: .4);
    expect(controller.slots[1].remaining, 8);
    await slideControl(tester, const Key('confirm-intake-slider'));
    expect(controller.slots[1].remaining, 7);
    expect(controller.intakeHistory.single.isPrn, isTrue);
    expect(
        controller.checkPrnStatus(controller.slots[1].drug!).canTake, isFalse);
    expect(tester.widget<FilledButton>(find.byKey(receive)).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('profile saves only after a full slide', (tester) async {
    final controller =
        await mount(tester, const Scaffold(body: ProfileScreen()));
    await tester.tap(find.byTooltip('แก้ไขข้อมูลผู้ป่วย'));
    await tester.pumpAndSettle();
    await slideControl(tester, const Key('confirm-action-slider'),
        fraction: .4);
    expect(find.byType(ProfileEditScreen), findsNothing);
    await slideControl(tester, const Key('confirm-action-slider'));
    await tester.enterText(find.byType(TextFormField).first, 'Edited Patient');
    const save = Key('save-profile-slider');
    await slideControl(tester, save, fraction: .4);
    expect(controller.profile.name, 'Patient');
    await slideControl(tester, save);
    expect(controller.profile.name, 'Edited Patient');
    expect(find.byType(ProfileEditScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reminder settings save only after a full slide', (tester) async {
    final controller = await mount(tester, const ReminderSettingsScreen());
    final field = find.byType(DropdownButtonFormField<int>).first;
    await tester.ensureVisible(field);
    await tester.tap(field);
    await tester.pumpAndSettle();
    await tester.tap(find.text('30 นาที').last);
    await tester.pumpAndSettle();
    const save = Key('save-reminders-slider');
    await slideControl(tester, save, fraction: .4);
    expect(controller.alertSettings.minutesBefore, 15);
    await slideControl(tester, save);
    expect(controller.alertSettings.minutesBefore, 30);
    expect(find.byType(ReminderSettingsScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('removing medication requires a full destructive slide',
      (tester) async {
    final controller = await mount(tester, const DispenserScreen());
    final slot = find.byKey(const ValueKey('medication-slot-1'));
    await tester.longPress(slot);
    await tester.pumpAndSettle();
    const confirm = Key('confirm-action-slider');
    await slideControl(tester, confirm, fraction: .4);
    expect(controller.slots.first.isEmpty, isFalse);
    await tester.tap(find.text('ยกเลิก'));
    await tester.pumpAndSettle();
    expect(controller.slots.first.isEmpty, isFalse);
    await tester.longPress(slot);
    await tester.pumpAndSettle();
    await slideControl(tester, confirm);
    expect(controller.slots.first.isEmpty, isTrue);
    expect(controller.drugs, hasLength(2));
    expect(tester.takeException(), isNull);
  });
}
