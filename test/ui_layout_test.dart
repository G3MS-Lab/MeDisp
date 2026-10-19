import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medisp/application/app_controller.dart';
import 'package:medisp/application/app_scope.dart';
import 'package:medisp/data/auth_repositories.dart';
import 'package:medisp/data/persistent_dispenser_repository.dart';
import 'package:medisp/data/persistent_medication_repository.dart';
import 'package:medisp/domain/models.dart';
import 'package:medisp/main.dart';
import 'package:medisp/screens/adherence_screen.dart';
import 'package:medisp/screens/all_drugs_screen.dart';
import 'package:medisp/screens/allergy_detail_screen.dart';
import 'package:medisp/screens/allergy_screen.dart';
import 'package:medisp/screens/auth_screen.dart';
import 'package:medisp/screens/daily_screen.dart';
import 'package:medisp/screens/dispenser_screen.dart';
import 'package:medisp/screens/drug_detail_screen.dart';
import 'package:medisp/screens/drug_form_screen.dart';
import 'package:medisp/screens/history_screen.dart';
import 'package:medisp/screens/hub_screen.dart';
import 'package:medisp/screens/intake_detail_screen.dart';
import 'package:medisp/screens/medication_refill_screen.dart';
import 'package:medisp/screens/profile_edit_screen.dart';
import 'package:medisp/screens/profile_screen.dart';
import 'package:medisp/screens/reminder_settings_screen.dart';
import 'package:medisp/theme/medis_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/slide_gesture.dart';

const _drug = Drug(
    id: 'scheduled',
    name: 'ยาประจำสำหรับดูแลสุขภาพ',
    notes: 'รับประทานตามคำแนะนำของแพทย์และเภสัชกร',
    instructions: [
      DoseInstruction(meal: MealType.breakfast, quantity: 1),
      DoseInstruction(meal: MealType.lunch, quantity: 1, beforeFood: false),
      DoseInstruction(meal: MealType.dinner, quantity: 1),
      DoseInstruction(meal: MealType.bedtime, quantity: 1),
    ]);
const _prn = Drug(
    id: 'prn',
    name: 'ยาตามอาการ',
    isPrn: true,
    prnConfig: PrnConfig(
        symptom: 'ปวดศีรษะหรือมีไข้',
        quantity: 1,
        minIntervalHours: 4,
        maxDosesPerDay: 4));

Future<AppController> _fixture() async {
  SharedPreferences.setMockInitialValues({});
  final auth = OfflineAuthRepository(MemoryAuthStorage());
  await auth.initialize();
  await auth.register(
      name: 'ผู้ใช้งานทดสอบ ภาษาไทย',
      email: 'ui@example.com',
      password: 'password');
  final controller = AppController(auth, PersistentDispenserRepository(auth),
      PersistentMedicationRepository(auth));
  await controller.initialize();
  await controller.toggleConnection();
  await controller.addDrugToSlot(_drug, 1, 15);
  await controller.addDrugToSlot(_prn, 2, 10);
  return controller;
}

Future<void> _capture(
    WidgetTester tester, GlobalKey key, String name, double width) async {
  if (Platform.environment['MEDISP_CAPTURE_UI'] != '1' || width != 430) return;
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory('build/ui-review').create(recursive: true);
    await File('build/ui-review/$name.png')
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final font = FontLoader('NotoSansThai')
      ..addFont(rootBundle.load('assets/fonts/NotoSansThai.ttf'));
    await font.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });

  for (final width in [320.0, 430.0, 640.0]) {
    testWidgets('all screens fit width $width with Thai text', (tester) async {
      tester.view.physicalSize = Size(width, 860);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = (await tester.runAsync(_fixture))!;
      final now = DateTime.now();
      final allergy = AllergyRecord(
          date: now,
          description: 'มีผื่นบริเวณแขนหลังรับประทานยา',
          symptoms: const {'ผื่น'});
      final intake = IntakeRecord(
          id: 'review',
          takenAt: now,
          meal: MealType.breakfast,
          doses: const [DrugDose(_drug, 1)]);
      final screens = <String, Widget>{
        'auth': const AuthScreen(),
        'shell': const MeDisShell(),
        'today': const Scaffold(body: SafeArea(child: DailyScreen())),
        'menu': const Scaffold(body: SafeArea(child: HubScreen())),
        'profile': const Scaffold(body: SafeArea(child: ProfileScreen())),
        'dispenser': const DispenserScreen(),
        'drug-detail': const DrugDetailScreen(drug: _drug),
        'prn-detail': const DrugDetailScreen(drug: _prn),
        'drug-form': DrugFormScreen(slot: controller.slots.first),
        'refill': MedicationRefillScreen(slot: controller.slots.first),
        'drugs': const AllDrugsScreen(),
        'history': const HistoryScreen(),
        'allergies': const AllergyScreen(),
        'allergy-detail': AllergyDetailScreen(record: allergy),
        'intake-detail': IntakeDetailScreen(record: intake),
        'profile-edit': const ProfileEditScreen(),
        'reminders': const ReminderSettingsScreen(),
        'adherence': const AdherenceScreen(),
      };
      for (final entry in screens.entries) {
        final capture = GlobalKey();
        await tester.pumpWidget(AppScope(
          controller: controller,
          child: MaterialApp(
            theme: MeDisTheme.light,
            locale: const Locale('th'),
            supportedLocales: const [Locale('th'), Locale('en')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(width == 320 ? 1.4 : 1)),
                child: child!),
            home: RepaintBoundary(key: capture, child: entry.value),
          ),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull,
            reason: '${entry.key} top at $width');
        await _capture(tester, capture, entry.key, width);
        if (entry.key == 'today') {
          await tester.tap(find.text('ตามอาการ'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'PRN top at $width');
          await _capture(tester, capture, 'today-prn', width);
          await tester.ensureVisible(find.byKey(const Key('receive-prn-2')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull,
              reason: 'PRN action at $width');
          final scroll = tester.state<ScrollableState>(find
              .byWidgetPredicate((widget) =>
                  widget is Scrollable &&
                  widget.axisDirection == AxisDirection.down)
              .first);
          scroll.position.jumpTo(0);
          await tester.pumpAndSettle();
          await tester.tap(find.text('ยาตามมื้อ'));
          await tester.pumpAndSettle();
        }
        final scrollables = find.byWidgetPredicate((widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down);
        if (scrollables.evaluate().isNotEmpty) {
          final state = tester.state<ScrollableState>(scrollables.first);
          var steps = 0;
          while (state.mounted &&
              state.position.pixels < state.position.maxScrollExtent &&
              steps++ < 25) {
            state.position.jumpTo(math.min(
                state.position.pixels + 350, state.position.maxScrollExtent));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull,
                reason: '${entry.key} scroll at $width');
          }
        }
      }
    });
  }
  testWidgets('allergy sheet validates inline and works with a phone keyboard',
      (tester) async {
    tester.view.physicalSize = const Size(320, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final controller = (await tester.runAsync(_fixture))!;
    await tester.pumpWidget(AppScope(
        controller: controller,
        child: MaterialApp(
            theme: MeDisTheme.light,
            locale: const Locale('th'),
            supportedLocales: const [Locale('th')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            home: const AllergyScreen())));
    await tester.pumpAndSettle();
    await tester.tap(find.text('เพิ่มอาการ'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    await slideControl(tester, const Key('confirm-action-slider'),
        fraction: .4);
    expect(find.byType(BottomSheet), findsNothing);
    await slideControl(tester, const Key('confirm-action-slider'));
    const save = Key('save-allergy-slider');
    await slideControl(tester, save);
    expect(find.text('เลือกอาการอย่างน้อย 1 รายการ'), findsOneWidget);
    await tester.ensureVisible(find.text('ผื่น *'));
    await tester.tap(find.text('ผื่น *'));
    await slideControl(tester, save);
    expect(find.text('ระบุลักษณะอาการหรือตำแหน่งที่เกิดอาการ'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'มีผื่นที่แขน');
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    await tester.pumpAndSettle();
    await slideControl(tester, save, fraction: .4);
    expect(controller.allergies, isEmpty);
    await slideControl(tester, save);
    expect(controller.allergies.single.description, 'มีผื่นที่แขน');
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
