import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medisp/application/app_controller.dart';
import 'package:medisp/application/app_scope.dart';
import 'package:medisp/data/auth_repositories.dart';
import 'package:medisp/data/persistent_dispenser_repository.dart';
import 'package:medisp/data/persistent_medication_repository.dart';
import 'package:medisp/domain/models.dart';
import 'package:medisp/screens/dispenser_screen.dart';
import 'package:medisp/screens/drug_detail_screen.dart';
import 'package:medisp/screens/drug_form_screen.dart';
import 'package:medisp/screens/medication_refill_screen.dart';
import 'package:medisp/widgets/medication_verify_image.dart';
import 'package:medisp/theme/medis_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<AppController> _mount(WidgetTester tester,
    {Drug? drug,
    bool connected = true,
    double width = 430,
    double textScale = 1}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final controller = (await tester.runAsync(() async {
    SharedPreferences.setMockInitialValues({});
    final auth = OfflineAuthRepository(MemoryAuthStorage());
    await auth.initialize();
    await auth.register(
        name: 'Patient', email: 'manage@example.com', password: 'password');
    final controller = AppController(auth, PersistentDispenserRepository(auth),
        PersistentMedicationRepository(auth));
    await controller.initialize();
    if (connected) await controller.toggleConnection();
    if (drug != null) await controller.addDrugToSlot(drug, 1, 7);
    return controller;
  }))!;
  await tester.pumpWidget(AppScope(
      controller: controller,
      child: MaterialApp(
        theme: MeDisTheme.light,
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!),
        home: const DispenserScreen(),
      )));
  await tester.pumpAndSettle();
  return controller;
}

Future<void> _slide(WidgetTester tester, {double fraction = 1}) async {
  final rect =
      tester.getRect(find.byKey(const Key('medication-confirmation-slider')));
  await tester.dragFrom(
      rect.centerLeft + const Offset(56, 0), Offset(rect.width * fraction, 0));
  await tester.pumpAndSettle();
}

Future<void> _slideSave(WidgetTester tester, {double fraction = 1}) async {
  final slider = find.byKey(const Key('slide-to-confirm'));
  final screen = find.byType(DrugFormScreen).evaluate().isNotEmpty
      ? find.byType(DrugFormScreen)
      : find.byType(MedicationRefillScreen);
  await tester.scrollUntilVisible(slider, 400,
      scrollable:
          find.descendant(of: screen, matching: find.byType(Scrollable)).first);
  await tester.ensureVisible(slider);
  await tester.pumpAndSettle();
  final rect = tester.getRect(slider);
  await tester.dragFrom(
      rect.centerLeft + const Offset(56, 0), Offset(rect.width * fraction, 0));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('empty slot opens add form as soon as the slide reaches the end',
      (tester) async {
    final controller = await _mount(tester);
    expect(find.byKey(const Key('add-medication')), findsNothing);
    expect(find.byKey(const Key('edit-medication')), findsNothing);
    expect(find.byKey(const Key('add-medication-slot-1')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('medication-slot-1')));
    await tester.pumpAndSettle();
    expect(find.byType(DrugFormScreen), findsNothing);
    expect(find.byKey(const Key('confirm-medication-change')), findsNothing);
    final confirmationSlider =
        find.byKey(const Key('medication-confirmation-slider'));
    expect(SliderTheme.of(tester.element(confirmationSlider)).trackHeight, 56);
    expect(find.text('สไลด์เพื่อเปิดฟอร์ม'), findsOneWidget);
    final slider = tester.getRect(find.byType(Slider));
    await tester.tapAt(slider.centerRight - const Offset(24, 0));
    await tester.pumpAndSettle();
    expect(find.byType(DrugFormScreen), findsNothing);
    await _slide(tester, fraction: .4);
    expect(find.byType(DrugFormScreen), findsNothing);
    expect(tester.widget<Slider>(find.byType(Slider)).value, 0);
    expect(controller.drugs, isEmpty);
    await _slide(tester);
    expect(find.byType(Slider), findsNothing);
    expect(find.text('เพิ่มยา · ช่อง 1'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'New medicine');
    final pickImage = find.byKey(const Key('pick-medication-image'));
    await tester.scrollUntilVisible(pickImage, 400,
        scrollable: find
            .descendant(
                of: find.byType(DrugFormScreen),
                matching: find.byType(Scrollable))
            .first);
    expect(find.byType(MedicationVerifyImage), findsOneWidget);
    expect(tester.getSize(pickImage).height, lessThan(60));
    await _slideSave(tester);
    expect(controller.drugs.single.name, 'New medicine');
    expect(controller.slots.first.remaining, 10);
    expect(find.byType(DrugFormScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'edit prefills and updates the existing drug while cancel leaves it unchanged',
      (tester) async {
    final original = Drug(
        id: 'existing',
        name: 'Original medicine',
        notes: 'Original notes',
        addedAt: DateTime(2026, 1, 1),
        labelImagePath: 'medisp-image:existing',
        isPrn: true,
        prnConfig: const PrnConfig(
            symptom: 'Original symptom',
            quantity: 2,
            minIntervalHours: 6,
            maxDosesPerDay: 6));
    final controller = await _mount(tester, drug: original);
    expect(find.byKey(const Key('edit-medication')), findsNothing);
    expect(find.byKey(const Key('change-medication-1')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('medication-slot-1')));
    await tester.pumpAndSettle();
    expect(find.byType(DrugDetailScreen), findsOneWidget);
    final edit = find.byKey(const Key('edit-medication'));
    expect(edit, findsOneWidget);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ยกเลิก'));
    await tester.pumpAndSettle();
    expect(controller.drugs.single.name, original.name);
    expect(find.byType(DrugFormScreen), findsNothing);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    await _slide(tester);
    expect(find.text('แก้ไขยา · ช่อง 1'), findsOneWidget);
    expect(find.text('Original medicine'), findsOneWidget);
    expect(find.text('Original notes'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'Edited medicine');
    await _slideSave(tester);
    expect(controller.drugs.single.id, original.id);
    expect(controller.drugs.single.name, 'Edited medicine');
    expect(controller.drugs.single.notes, original.notes);
    expect(controller.drugs.single.addedAt, original.addedAt);
    expect(controller.drugs.single.labelImagePath, original.labelImagePath);
    expect(controller.drugs.single.prnConfig?.symptom, 'Original symptom');
    expect(controller.drugs.single.prnConfig?.quantity, 2);
    expect(controller.drugs.single.prnConfig?.minIntervalHours, 6);
    expect(controller.drugs.single.prnConfig?.maxDosesPerDay, 6);
    expect(controller.slots.first.remaining, 7);
    expect(find.byType(DrugFormScreen), findsNothing);
    expect(find.byType(DrugDetailScreen), findsOneWidget);
    expect(find.text('Edited medicine'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disconnected management disables adding and editing',
      (tester) async {
    final controller =
        await _mount(tester, drug: const Drug(id: 'one', name: 'Medicine'));
    await tester.runAsync(controller.toggleConnection);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('add-medication')), findsNothing);
    expect(find.byKey(const Key('change-medication-1')), findsNothing);
    expect(find.byKey(const Key('add-medication-slot-2')), findsNothing);
    expect(
        tester
            .widget<InkWell>(find.descendant(
                of: find.byKey(const ValueKey('medication-slot-2')),
                matching: find.byType(InkWell)))
            .onTap,
        isNull);
    await tester.tap(find.byKey(const ValueKey('medication-slot-1')));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('edit-medication')))
            .onPressed,
        isNull);
    expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('refill-medication')))
            .onPressed,
        isNull);
  });

  testWidgets(
      'detail refill verifies the label and adds pills after final slide',
      (tester) async {
    final controller =
        await _mount(tester, drug: const Drug(id: 'one', name: 'Medicine'));
    await tester.tap(find.byKey(const ValueKey('medication-slot-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('refill-medication')));
    await tester.pumpAndSettle();
    expect(find.byType(MedicationRefillScreen), findsNothing);
    await _slide(tester);
    expect(find.byType(MedicationRefillScreen), findsOneWidget);
    expect(find.text('ตรวจสอบยาก่อนใส่เครื่อง'), findsOneWidget);
    await tester.tap(find.byKey(const Key('increase-refill')));
    await tester.pumpAndSettle();
    expect(find.text('หลังเพิ่มจะมี 9 เม็ดในช่อง'), findsOneWidget);
    expect(controller.slots.first.remaining, 7);
    await _slideSave(tester, fraction: .4);
    expect(controller.slots.first.remaining, 7);
    expect(find.byType(MedicationRefillScreen), findsOneWidget);
    await _slideSave(tester);
    expect(controller.slots.first.remaining, 9);
    expect(find.byType(MedicationRefillScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('slot actions fit a narrow screen with larger text',
      (tester) async {
    await _mount(tester,
        width: 320,
        textScale: 1.5,
        drug: const Drug(id: 'one', name: 'Medicine'));
    expect(find.text('แก้ไข'), findsNothing);
    expect(find.byKey(const Key('add-medication-slot-2')), findsNothing);
    expect(find.text('แตะเพื่อเพิ่มยา'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
