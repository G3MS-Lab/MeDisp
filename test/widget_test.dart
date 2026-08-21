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
                date: date, description: 'rash', symptoms: const {'มีผื่น'})
          ],
          onDateSelected: (_) {})
    ]))));

    expect(find.text('สิงหาคม 2569'), findsOneWidget);
    expect(find.text('ยาเช้า'), findsOneWidget);
    expect(find.text('อาการแพ้'), findsOneWidget);
    expect(find.byIcon(Icons.warning_rounded), findsNWidgets(2));
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
    await auth.register(
        name: 'Patient', email: 'patient@example.com', password: 'password');
    final controller = AppController(auth, PersistentDispenserRepository(auth),
        PersistentMedicationRepository(auth));
    await tester.pumpWidget(AppScope(
        controller: controller, child: MeDisApp(controller: controller)));
    await tester.pumpAndSettle();

    expect(find.text('Daily Check List'), findsOneWidget);
    expect(find.textContaining('วันนี้ทานแล้ว'), findsOneWidget);
  });
}
