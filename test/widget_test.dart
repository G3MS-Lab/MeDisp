import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medisp/application/app_controller.dart';
import 'package:medisp/application/app_scope.dart';
import 'package:medisp/data/auth_repositories.dart';
import 'package:medisp/data/persistent_dispenser_repository.dart';
import 'package:medisp/data/persistent_medication_repository.dart';
import 'package:medisp/main.dart';
import 'package:medisp/domain/models.dart';
import 'package:medisp/widgets/medis_event_calendar.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('shared calendar renders medication and allergy markers',
      (tester) async {
    final date = DateTime(2026, 8, 9, 8, 30);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ListView(children: [
      MeDisEventCalendar(
          selectedDate: date,
          intakes: [
            IntakeRecord(
                id: 'intake',
                takenAt: date,
                meal: MealType.breakfast,
                doses: const [])
          ],
          allergies: [
            AllergyRecord(
                date: date, description: 'rash', symptoms: const {'ผื่น'})
          ],
          onDateSelected: (_) {})
    ]))));

    expect(find.text('สิงหาคม 2569'), findsOneWidget);
    expect(find.text('ยาเช้า'), findsOneWidget);
    expect(find.text('อาการไม่พึงประสงค์'), findsOneWidget);
    expect(find.byIcon(Icons.warning_rounded), findsNWidgets(2));
  });

  testWidgets('calendar cells render medication intake status', (tester) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 8);
    final past = today.subtract(const Duration(days: 1));
    final pastMissed = today.subtract(const Duration(days: 2));

    final drug = Drug(
      id: 'scheduled-drug',
      name: 'ยาประจำ',
      addedAt: pastMissed.subtract(const Duration(days: 1)),
      instructions: const [
        DoseInstruction(meal: MealType.breakfast, quantity: 1),
        DoseInstruction(meal: MealType.dinner, quantity: 1),
      ],
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(
          children: [
            MeDisEventCalendar(
              selectedDate: today,
              drugs: [drug],
              intakes: [
                // Past day: complete (breakfast and dinner)
                IntakeRecord(
                    id: 'past-1',
                    takenAt: past,
                    meal: MealType.breakfast,
                    doses: const []),
                IntakeRecord(
                    id: 'past-2',
                    takenAt: past,
                    meal: MealType.dinner,
                    doses: const []),
                // Today: partial (breakfast only)
                IntakeRecord(
                    id: 'today-1',
                    takenAt: today,
                    meal: MealType.breakfast,
                    doses: const []),
              ],
              allergies: const [],
              onDateSelected: (_) {},
            ),
          ],
        ),
      ),
    ));

    // Legend items
    expect(find.text('ทานครบ'), findsWidgets);
    expect(find.text('ทานบางส่วน'), findsWidgets);
    expect(find.text('ไม่ได้ทาน'), findsWidgets);
  });

  testWidgets('initializes an unauthenticated app after the first frame',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final auth = OfflineAuthRepository(MemoryAuthStorage());
    await auth.initialize();
    final controller = AppController(auth, PersistentDispenserRepository(auth),
        PersistentMedicationRepository(auth));

    await tester.pumpWidget(AppScope(
        controller: controller, child: MeDisApp(controller: controller)));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('เข้าสู่ระบบเพื่อจัดการยา'), findsOneWidget);
  });

  testWidgets('MeDis opens the daily checklist', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final auth = OfflineAuthRepository(MemoryAuthStorage());
    await auth.initialize();
    await tester.runAsync(() => auth.register(
        name: 'Patient', email: 'patient@example.com', password: 'password'));
    final controller = AppController(auth, PersistentDispenserRepository(auth),
        PersistentMedicationRepository(auth));
    await tester.pumpWidget(AppScope(
        controller: controller, child: MeDisApp(controller: controller)));
    await tester.pumpAndSettle();

    expect(find.text('ยาวันนี้'), findsOneWidget);
    expect(find.textContaining('วันนี้ทานแล้ว'), findsOneWidget);
  });

  testWidgets(
      'Daily checklist switches between scheduled meals and PRN slide tabs',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final auth = OfflineAuthRepository(MemoryAuthStorage());
    await auth.initialize();
    await tester.runAsync(() => auth.register(
        name: 'Patient', email: 'patient@example.com', password: 'password'));
    final controller = AppController(auth, PersistentDispenserRepository(auth),
        PersistentMedicationRepository(auth));
    await tester.pumpWidget(AppScope(
        controller: controller, child: MeDisApp(controller: controller)));
    await tester.pumpAndSettle();

    expect(find.text('ยาตามมื้อ'), findsOneWidget);
    expect(find.text('ตามอาการ'), findsOneWidget);
    expect(find.textContaining('วันนี้ทานแล้ว'), findsOneWidget);

    // Tap PRN tab
    await tester.tap(find.text('ตามอาการ'));
    await tester.pumpAndSettle();

    expect(find.text('ยาตามอาการในตู้ (0 รายการ)'), findsOneWidget);
    expect(find.text('ยังไม่มียาตามอาการในตู้จ่ายยา'), findsOneWidget);

    // Tap back to scheduled meals
    await tester.tap(find.text('ยาตามมื้อ'));
    await tester.pumpAndSettle();
    expect(find.textContaining('วันนี้ทานแล้ว'), findsOneWidget);
  });
}
