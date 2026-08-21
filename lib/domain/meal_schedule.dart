import 'models.dart';

class MealSchedule {
  const MealSchedule._();

  static MealPlan? current(Iterable<MealPlan> meals, DateTime now) {
    MealPlan? closest;
    var closestDistance = 24 * 60 + 1;
    final currentMinute = now.hour * 60 + now.minute;
    for (final meal in meals) {
      final mealMinute = meal.time.hour * 60 + meal.time.minute;
      final direct = (mealMinute - currentMinute).abs();
      final distance = direct > 12 * 60 ? 24 * 60 - direct : direct;
      if (distance < closestDistance) {
        closest = meal;
        closestDistance = distance;
      }
    }
    return closest;
  }
}
