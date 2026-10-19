import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:medisp/application/app_controller.dart';
import 'package:medisp/application/app_scope.dart';
import 'package:medisp/data/auth_repositories.dart';
import 'package:medisp/data/persistent_dispenser_repository.dart';
import 'package:medisp/data/persistent_medication_repository.dart';
import 'package:medisp/domain/models.dart';
import 'package:medisp/screens/daily_screen.dart';
import 'package:medisp/theme/medis_theme.dart';
import 'package:medisp/widgets/pill_character.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/slide_gesture.dart';

Future<AppController> _createFixture() async {
  SharedPreferences.setMockInitialValues({});
  final auth = OfflineAuthRepository(MemoryAuthStorage());
  await auth.initialize();
  await auth.register(
      name: 'Patient', email: 'carousel@example.com', password: 'password');
  final controller = AppController(
      auth,
      PersistentDispenserRepository(auth),
      PersistentMedicationRepository(auth));
  await controller.initialize();
  await controller.toggleConnection();

  // Drug 1: Breakfast before food
  await controller.addDrugToSlot(
      const Drug(
        id: 'bf-before',
        name: 'ยาเช้าก่อนอาหาร',
        instructions: [
          DoseInstruction(
              meal: MealType.breakfast, quantity: 1, beforeFood: true),
        ],
      ),
      1,
      10);

  // Drug 2: Breakfast after food
  await controller.addDrugToSlot(
      const Drug(
        id: 'bf-after',
        name: 'ยาเช้าหลังอาหาร',
        instructions: [
          DoseInstruction(
              meal: MealType.breakfast, quantity: 2, beforeFood: false),
        ],
      ),
      2,
      10);

  // Drug 3: Dinner before food
  await controller.addDrugToSlot(
      const Drug(
        id: 'din-before',
        name: 'ยาเย็นก่อนอาหาร',
        instructions: [
          DoseInstruction(
              meal: MealType.dinner, quantity: 1, beforeFood: true),
        ],
      ),
      3,
      10);

  // Drug 4: Bedtime (must have no before/after food distinction)
  await controller.addDrugToSlot(
      const Drug(
        id: 'bed-drug',
        name: 'ยาก่อนนอน',
        instructions: [
          DoseInstruction(
              meal: MealType.bedtime, quantity: 1, beforeFood: true),
        ],
      ),
      4,
      10);
  return controller;
}

void main() {
  testWidgets(
      'splits meals into separate before/after cards and navigates via curved swipe',
      (tester) async {
    tester.view.physicalSize = const Size(430, 956);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = (await tester.runAsync(_createFixture))!;

    await tester.pumpWidget(
      AppScope(
        controller: controller,
        child: MaterialApp(
          theme: MeDisTheme.light,
          home: const Scaffold(body: DailyScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Check header displays 4 cards
    expect(find.textContaining('วันนี้ทานแล้ว 0 จาก 4 มื้อ'), findsOneWidget);

    // Initial card defaults to upcoming meal (Dinner in afternoon/evening)
    expect(find.text('เย็น · ก่อนอาหาร'), findsOneWidget);
    expect(find.text('ยาเย็นก่อนอาหาร'), findsOneWidget);

    // Verify cartoon character is displayed directly above the active meal card
    expect(find.byType(PillCharacterWidget), findsOneWidget);
    final initialCharacter =
        tester.widget<PillCharacterWidget>(find.byType(PillCharacterWidget));
    expect(initialCharacter.meal, MealType.dinner);
    expect(initialCharacter.isTaken, isFalse);

    // Verify current meal card border has dinner color (0xFFFF8A5B)
    final cardFinder = find
        .ancestor(
          of: find.text('เย็น · ก่อนอาหาร'),
          matching: find.byType(Container),
        )
        .first;
    final cartoonBottom =
        tester.getBottomLeft(find.byType(PillCharacterWidget)).dy;
    final cardTop = tester.getTopLeft(cardFinder).dy;
    expect(cartoonBottom, lessThanOrEqualTo(cardTop));

    final cardContainer = tester
        .widgetList<Container>(find.ancestor(
          of: find.text('เย็น · ก่อนอาหาร'),
          matching: find.byType(Container),
        ))
        .firstWhere((c) =>
            c.decoration is BoxDecoration &&
            (c.decoration as BoxDecoration).border?.isUniform == true);
    final border = (cardContainer.decoration as BoxDecoration).border as Border;
    expect(border.top.color, MealType.dinner.color);

    // Swipe left to bedtime card
    await tester.drag(
        find.byKey(const Key('curved-meal-carousel-pageview')),
        const Offset(-300, 0));
    await tester.pumpAndSettle();

    // Bedtime must show ONLY 'ก่อนนอน' (no before or after food)
    expect(find.text('ก่อนนอน'), findsOneWidget);
    expect(find.text('ก่อนนอน · ก่อนอาหาร'), findsNothing);
    expect(find.text('ก่อนนอน · หลังอาหาร'), findsNothing);
    expect(find.text('ยาก่อนนอน'), findsOneWidget);

    // Active cartoon character updates to bedtime
    final bedtimeCharacter =
        tester.widget<PillCharacterWidget>(find.byType(PillCharacterWidget));
    expect(bedtimeCharacter.meal, MealType.bedtime);
    expect(bedtimeCharacter.isTaken, isFalse);

    // Jump button is active to return to current meal
    const jumpButton = Key('jump-to-current-meal-button');
    expect(find.byKey(jumpButton), findsOneWidget);
    await tester.tap(find.byKey(jumpButton));
    await tester.pumpAndSettle();

    // Successfully returned to current meal (Dinner)
    expect(find.text('เย็น · ก่อนอาหาร'), findsOneWidget);

    // Swipe right (Offset > 0) to navigate to previous card: 'เช้า · หลังอาหาร'
    await tester.drag(
        find.byKey(const Key('curved-meal-carousel-pageview')),
        const Offset(300, 0));
    await tester.pumpAndSettle();

    expect(find.text('เช้า · หลังอาหาร'), findsOneWidget);
    expect(find.text('ยาเช้าหลังอาหาร'), findsOneWidget);
    final breakfastCharacter =
        tester.widget<PillCharacterWidget>(find.byType(PillCharacterWidget));
    expect(breakfastCharacter.meal, MealType.breakfast);

    // Jump back to current meal via button again
    await tester.tap(find.byKey(jumpButton));
    await tester.pumpAndSettle();
    expect(find.text('เย็น · ก่อนอาหาร'), findsOneWidget);

    // Take medication for current meal (dinner)
    const receiveDinner = Key('receive-meal-dinner');
    await tester.tap(find.byKey(receiveDinner));
    await tester.pumpAndSettle();

    expect(find.text('ตรวจสอบยาก่อนทาน'), findsOneWidget);
    expect(find.text('ยาเย็นก่อนอาหาร'), findsWidgets);

    // Slide to confirm
    await slideControl(tester, const Key('confirm-intake-slider'));
    await tester.pumpAndSettle();

    // Dinner before food should now be marked as completed and cartoon becomes happy (isTaken: true)
    expect(find.textContaining('วันนี้ทานแล้ว 1 จาก 4 มื้อ'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(receiveDinner)).onPressed,
        isNull);
    final completedCharacter =
        tester.widget<PillCharacterWidget>(find.byType(PillCharacterWidget));
    expect(completedCharacter.meal, MealType.dinner);
    expect(completedCharacter.isTaken, isTrue);

    // Warning notice should be removed
    expect(find.text('ใช้ยาตามคำแนะนำของแพทย์หรือเภสัชกร'), findsNothing);
  });

  testWidgets(
      'PillCharacterWidget animates and renders palettes for all MealType, PRN green character, and taken states',
      (tester) async {
    for (final meal in MealType.values) {
      for (final isTaken in [false, true]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: PillCharacterWidget(
                  meal: meal,
                  isTaken: isTaken,
                  animate: true,
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        expect(find.byType(PillCharacterWidget), findsOneWidget);
      }
    }

    // Verify PRN green character in idle & taken states
    for (final isTaken in [false, true]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PillSceneBackground(
              isPrn: true,
              isTaken: isTaken,
              child: Center(
                child: PillCharacterWidget(
                  isPrn: true,
                  isTaken: isTaken,
                  animate: true,
                  showBackground: false,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));
      expect(tester.takeException(), isNull);
    }

    // Verify morphing between two meals
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: PillCharacterWidget(
              meal: MealType.breakfast,
              isTaken: false,
              morphToMeal: MealType.lunch,
              morphToIsTaken: false,
              morphProgress: 0.5,
              animate: true,
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));
    expect(tester.takeException(), isNull);
  });
}
