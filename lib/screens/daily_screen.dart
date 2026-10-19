import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/medis_theme.dart';

import '../application/app_controller.dart';
import '../application/app_scope.dart';
import '../domain/meal_schedule.dart';
import '../domain/models.dart';
import '../widgets/local_image.dart';
import '../widgets/medis_ui.dart';
import '../widgets/slide_to_confirm.dart';
import '../widgets/medication_card.dart';
import 'dispenser_screen.dart';
import 'drug_detail_screen.dart';

class DailyScreen extends StatelessWidget {
  const DailyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final done = controller.todayMeals.where((meal) => meal.completed).length;
    final currentMeal =
        MealSchedule.current(controller.todayMeals, DateTime.now());
    final prnSlots = controller.prnSlots;

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Column(
              children: [
                const _TodayBanner(),
                const SizedBox(height: 16),
                const _SlidingTabBar(),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: TabBarView(
              children: [
                _ScheduledMealsTab(
                  done: done,
                  currentMeal: currentMeal,
                ),
                _PrnTab(
                  prnSlots: prnSlots,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayBanner extends StatelessWidget {
  const _TodayBanner();

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(MeDisRadius.card),
        child: Stack(children: [
          Positioned.fill(
              child: Image.asset('assets/images/daily_header.png',
                  fit: BoxFit.cover, excludeFromSemantics: true)),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(children: [
              Flexible(
                  flex: 4,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .96),
                        borderRadius: BorderRadius.circular(MeDisRadius.input)),
                    child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('ยาวันนี้',
                              style: TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.w700,
                                  color: MeDisColors.text,
                                  height: 1.4)),
                          SizedBox(height: 4),
                          Text('ทานยาตรงเวลา\nดูแลสุขภาพทุกวัน',
                              style: TextStyle(
                                  fontSize: 16,
                                  color: MeDisColors.muted,
                                  height: 1.5)),
                        ]),
                  )),
              const Spacer(),
            ]),
          ),
        ]),
      );
}

class _SlidingTabBar extends StatelessWidget {
  const _SlidingTabBar();
  @override
  Widget build(BuildContext context) => Container(
        height: 64,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
            color: MeDisColors.primarySoft,
            borderRadius: BorderRadius.circular(MeDisRadius.card)),
        child: TabBar(
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: Colors.transparent,
          labelPadding: const EdgeInsets.symmetric(horizontal: 4),
          indicator: BoxDecoration(
              color: MeDisColors.surface,
              borderRadius: BorderRadius.circular(MeDisRadius.input)),
          labelColor: MeDisColors.primary,
          unselectedLabelColor: MeDisColors.muted,
          labelStyle:
              const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          unselectedLabelStyle:
              const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          tabs: const [Tab(text: 'ยาตามมื้อ'), Tab(text: 'ตามอาการ')],
        ),
      );
}

class ScheduledMealCardData {
  final MealPlan meal;
  final MealType mealType;
  final bool? beforeFood;
  final List<DrugDose> doses;
  final TimeOfDay time;
  final bool isCompleted;
  final bool isCurrent;
  final String buttonKeyName;

  const ScheduledMealCardData({
    required this.meal,
    required this.mealType,
    required this.beforeFood,
    required this.doses,
    required this.time,
    required this.isCompleted,
    required this.isCurrent,
    required this.buttonKeyName,
  });

  int get totalPills => doses.fold(0, (sum, item) => sum + item.quantity);

  String get title {
    if (mealType == MealType.bedtime) {
      return 'ก่อนนอน';
    }
    return '${mealType.label} · ${beforeFood == false ? "หลังอาหาร" : "ก่อนอาหาร"}';
  }

  IconData get icon => switch (mealType) {
        MealType.breakfast => Icons.wb_sunny_rounded,
        MealType.lunch => Icons.light_mode_rounded,
        MealType.dinner => Icons.wb_twilight_rounded,
        MealType.bedtime => Icons.bedtime_rounded,
      };

  Color get color => mealType.color;
}

List<ScheduledMealCardData> _buildMealCards(
    AppController controller, MealPlan? currentMeal) {
  final now = DateTime.now();
  final todayIntakes = controller.intakeHistory
      .where((r) =>
          !r.isPrn && r.meal != null && DateUtils.isSameDay(r.takenAt, now))
      .toList();

  final cards = <ScheduledMealCardData>[];

  for (final meal in controller.todayMeals) {
    bool checkDosesCompleted(List<DrugDose> doses) {
      if (doses.isEmpty) return false;
      if (meal.completed) return true;
      final mealIntakes = todayIntakes.where((r) => r.meal == meal.type);
      final takenDrugIds =
          mealIntakes.expand((r) => r.doses.map((d) => d.drug.id)).toSet();
      return doses.every((d) => takenDrugIds.contains(d.drug.id));
    }

    // Bedtime has NO before-food or after-food distinction
    if (meal.type == MealType.bedtime) {
      final isComp = checkDosesCompleted(meal.drugs);
      cards.add(ScheduledMealCardData(
        meal: meal,
        mealType: meal.type,
        beforeFood: null,
        doses: meal.drugs,
        time: meal.time,
        isCompleted: isComp,
        isCurrent: meal.type == currentMeal?.type,
        buttonKeyName: 'receive-meal-${meal.type.name}',
      ));
      continue;
    }

    final beforeFoodDoses = meal.drugs
        .where(
            (dose) => dose.drug.instructionFor(meal.type)?.beforeFood ?? true)
        .toList();
    final afterFoodDoses = meal.drugs
        .where((dose) =>
            !(dose.drug.instructionFor(meal.type)?.beforeFood ?? true))
        .toList();

    if (beforeFoodDoses.isNotEmpty) {
      final isComp = checkDosesCompleted(beforeFoodDoses);
      cards.add(ScheduledMealCardData(
        meal: meal,
        mealType: meal.type,
        beforeFood: true,
        doses: beforeFoodDoses,
        time: meal.time,
        isCompleted: isComp,
        isCurrent: meal.type == currentMeal?.type,
        buttonKeyName: 'receive-meal-${meal.type.name}',
      ));
    }

    if (afterFoodDoses.isNotEmpty) {
      final isComp = checkDosesCompleted(afterFoodDoses);
      cards.add(ScheduledMealCardData(
        meal: meal,
        mealType: meal.type,
        beforeFood: false,
        doses: afterFoodDoses,
        time: meal.time,
        isCompleted: isComp,
        isCurrent: meal.type == currentMeal?.type,
        buttonKeyName: beforeFoodDoses.isEmpty
            ? 'receive-meal-${meal.type.name}'
            : 'receive-meal-${meal.type.name}-after',
      ));
    }
  }

  return cards;
}

int _calculateInitialIndex(
    List<ScheduledMealCardData> cards, MealPlan? currentMeal) {
  if (cards.isEmpty) return 0;
  // 1. Prioritize current meal that is not yet completed
  if (currentMeal != null) {
    final curIdx = cards
        .indexWhere((c) => c.mealType == currentMeal.type && !c.isCompleted);
    if (curIdx != -1) return curIdx;
  }
  // 2. Prioritize first incomplete card
  final firstIncomplete = cards.indexWhere((c) => !c.isCompleted);
  if (firstIncomplete != -1) return firstIncomplete;
  // 3. Fallback to currentMeal card if present
  if (currentMeal != null) {
    final curIdx = cards.indexWhere((c) => c.mealType == currentMeal.type);
    if (curIdx != -1) return curIdx;
  }
  return 0;
}

int _findCurrentMealIndex(
    List<ScheduledMealCardData> cards, MealPlan? currentMeal) {
  if (cards.isEmpty || currentMeal == null) return -1;
  final idx = cards
      .indexWhere((c) => c.mealType == currentMeal.type && !c.isCompleted);
  if (idx != -1) return idx;
  return cards.indexWhere((c) => c.mealType == currentMeal.type);
}

class _ScheduledMealsTab extends StatelessWidget {
  const _ScheduledMealsTab({
    required this.done,
    required this.currentMeal,
  });

  final int done;
  final MealPlan? currentMeal;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final cards = _buildMealCards(controller, currentMeal);
    final initialIndex = _calculateInitialIndex(cards, currentMeal);
    final currentMealIndex = _findCurrentMealIndex(cards, currentMeal);
    final completedCount = cards.where((c) => c.isCompleted).length;

    if (cards.isEmpty) {
      return ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: const [
          Text('วันนี้ทานแล้ว 0 จาก 0 มื้อ',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          SizedBox(height: 12),
          _EmptyPlan(),
          SizedBox(height: 12),
          MeDisNotice(message: 'ใช้ยาตามคำแนะนำของแพทย์หรือเภสัชกร'),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'วันนี้ทานแล้ว $completedCount จาก ${cards.length} มื้อ',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  minHeight: 6,
                  value: cards.isEmpty ? 0.0 : completedCount / cards.length,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _CurvedMealCarousel(
            cards: cards,
            initialIndex: initialIndex,
            currentMealIndex: currentMealIndex,
            onCompleteCard: (card) async {
              try {
                await controller.completeMeal(card.mealType, doses: card.doses);
              } catch (error) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(
                          error.toString().replaceFirst('Bad state: ', ''))));
                }
              }
            },
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 4, 20, 14),
          child: MeDisNotice(message: 'ใช้ยาตามคำแนะนำของแพทย์หรือเภสัชกร'),
        ),
      ],
    );
  }
}

class _CurvedMealCarousel extends StatefulWidget {
  const _CurvedMealCarousel({
    required this.cards,
    required this.initialIndex,
    required this.currentMealIndex,
    required this.onCompleteCard,
  });

  final List<ScheduledMealCardData> cards;
  final int initialIndex;
  final int currentMealIndex;
  final Future<void> Function(ScheduledMealCardData card) onCompleteCard;

  @override
  State<_CurvedMealCarousel> createState() => _CurvedMealCarouselState();
}

class _CurvedMealCarouselState extends State<_CurvedMealCarousel> {
  late PageController _pageController;
  late int _currentPage;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.initialIndex.clamp(
        0, widget.cards.isEmpty ? 0 : widget.cards.length - 1);
    _pageController = PageController(
      initialPage: _currentPage,
      viewportFraction: 0.88,
    );
  }

  @override
  void didUpdateWidget(covariant _CurvedMealCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_currentPage >= widget.cards.length && widget.cards.isNotEmpty) {
      _currentPage = widget.cards.length - 1;
      _pageController.jumpToPage(_currentPage);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToPage(int page) {
    if (page < 0 || page >= widget.cards.length) return;
    setState(() => _currentPage = page);
    _pageController.animateToPage(
      page,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.cards.isEmpty) return const _EmptyPlan();

    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            key: const Key('curved-meal-carousel-pageview'),
            controller: _pageController,
            physics: const BouncingScrollPhysics(),
            itemCount: widget.cards.length,
            onPageChanged: (index) {
              setState(() => _currentPage = index);
            },
            itemBuilder: (context, index) {
              final card = widget.cards[index];
              return AnimatedBuilder(
                animation: _pageController,
                builder: (context, child) {
                  double diff = 0.0;
                  if (_pageController.position.haveDimensions) {
                    final page =
                        _pageController.page ?? _currentPage.toDouble();
                    diff = index - page;
                  } else {
                    diff = (index - _currentPage).toDouble();
                  }

                  final absDiff = diff.abs().clamp(0.0, 2.0);
                  // Curve physics: dips down in a smooth arc
                  final dy = math.pow(absDiff, 1.8) * 32.0;
                  // Rotation angle: tilts along tangent
                  final rotation = diff * 0.055;
                  // Scale and opacity
                  final scale = (1.0 - absDiff * 0.08).clamp(0.85, 1.0);
                  final opacity = (1.0 - absDiff * 0.35).clamp(0.4, 1.0);

                  return Transform.translate(
                    offset: Offset(0.0, dy),
                    child: Transform.rotate(
                      angle: rotation,
                      child: Transform.scale(
                        scale: scale,
                        child: Opacity(
                          opacity: opacity,
                          child: child,
                        ),
                      ),
                    ),
                  );
                },
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: _SingleMealCard(
                    card: card,
                    onComplete: () => widget.onCompleteCard(card),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        _PageDots(
          count: widget.cards.length,
          currentIndex: _currentPage,
          onTap: _goToPage,
        ),
        if (widget.currentMealIndex != -1) ...[
          const SizedBox(height: 4),
          _JumpToCurrentMealButton(
            isAlreadyOnCurrent: _currentPage == widget.currentMealIndex,
            currentMealTitle: widget.cards[widget.currentMealIndex].title,
            onPressed: _currentPage == widget.currentMealIndex
                ? null
                : () => _goToPage(widget.currentMealIndex),
          ),
        ],
      ],
    );
  }
}

class _JumpToCurrentMealButton extends StatelessWidget {
  const _JumpToCurrentMealButton({
    required this.isAlreadyOnCurrent,
    required this.currentMealTitle,
    required this.onPressed,
  });

  final bool isAlreadyOnCurrent;
  final String currentMealTitle;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 250),
      opacity: isAlreadyOnCurrent ? 0.6 : 1.0,
      child: TextButton.icon(
        key: const Key('jump-to-current-meal-button'),
        onPressed: onPressed,
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          backgroundColor: isAlreadyOnCurrent
              ? Colors.transparent
              : MeDisColors.primary.withValues(alpha: 0.1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: isAlreadyOnCurrent
                  ? MeDisColors.border.withValues(alpha: 0.5)
                  : MeDisColors.primary.withValues(alpha: 0.35),
            ),
          ),
        ),
        icon: Icon(
          Icons.my_location_rounded,
          size: 16,
          color: isAlreadyOnCurrent ? MeDisColors.muted : MeDisColors.primary,
        ),
        label: Text(
          isAlreadyOnCurrent
              ? 'มื้อปัจจุบัน ($currentMealTitle)'
              : 'ไปที่มื้อปัจจุบัน ($currentMealTitle)',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: isAlreadyOnCurrent ? MeDisColors.muted : MeDisColors.primary,
          ),
        ),
      ),
    );
  }
}

class _PageDots extends StatelessWidget {
  const _PageDots({
    required this.count,
    required this.currentIndex,
    required this.onTap,
  });

  final int count;
  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    if (count <= 1) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (index) {
        final isSelected = index == currentIndex;
        return GestureDetector(
          onTap: () => onTap(index),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: isSelected ? 22 : 7,
            height: 7,
            decoration: BoxDecoration(
              color: isSelected
                  ? MeDisColors.primary
                  : MeDisColors.muted.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        );
      }),
    );
  }
}

class _SingleMealCard extends StatefulWidget {
  const _SingleMealCard({
    required this.card,
    required this.onComplete,
  });

  final ScheduledMealCardData card;
  final Future<void> Function() onComplete;

  @override
  State<_SingleMealCard> createState() => _SingleMealCardState();
}

class _SingleMealCardState extends State<_SingleMealCard> {
  bool completing = false;

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    final connected = AppScope.of(context).connected;
    final canReceive = !card.isCompleted && card.isCurrent && connected;
    final cardBorderColor = card.isCurrent
        ? card.color
        : card.isCompleted
            ? MeDisColors.success.withValues(alpha: 0.3)
            : MeDisColors.border;

    return Container(
      decoration: BoxDecoration(
        color: MeDisColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: cardBorderColor,
          width: card.isCurrent ? 2.2 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: card.isCurrent
                ? card.color.withValues(alpha: 0.22)
                : Colors.black.withValues(alpha: 0.06),
            blurRadius: card.isCurrent ? 14 : 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            decoration: BoxDecoration(
              color: card.color.withValues(alpha: 0.1),
              border: Border(
                bottom: BorderSide(
                  color: card.color.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: card.color.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(card.icon, color: card.color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        card.title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: MeDisColors.text,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          const Icon(Icons.access_time_rounded,
                              size: 14, color: MeDisColors.muted),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              '${card.time.format24Hour()} น. · ${card.totalPills} เม็ด (${card.doses.length} รายการ)',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: MeDisColors.muted,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                if (card.isCompleted)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: MeDisColors.success.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_rounded,
                            size: 15, color: MeDisColors.success),
                        SizedBox(width: 4),
                        Text('ทานแล้ว',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: MeDisColors.success)),
                      ],
                    ),
                  )
                else if (card.isCurrent)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: MeDisColors.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.notifications_active_outlined,
                            size: 15, color: MeDisColors.primary),
                        SizedBox(width: 4),
                        Text('มื้อนี้',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: MeDisColors.primary)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              itemCount: card.doses.length,
              separatorBuilder: (_, __) => const Divider(height: 12),
              itemBuilder: (context, idx) {
                final dose = card.doses[idx];
                return InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DrugDetailScreen(drug: dose.drug),
                    ),
                  ),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            width: 46,
                            height: 46,
                            child: dose.drug.labelImagePath == null
                                ? Container(
                                    color: MeDisColors.primarySoft,
                                    child: const Icon(
                                      Icons.medication_outlined,
                                      color: MeDisColors.primary,
                                      size: 24,
                                    ),
                                  )
                                : localImage(
                                    dose.drug.labelImagePath!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Icon(
                                        Icons.broken_image_outlined),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                dose.drug.name,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: MeDisColors.text,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'ครั้งละ ${dose.quantity} เม็ด',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: card.color,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right,
                            color: MeDisColors.muted, size: 20),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton.icon(
                key: Key(card.buttonKeyName),
                onPressed: (canReceive && !completing)
                    ? () async {
                        final confirmed =
                            await _confirmMedicine(context, card.doses);
                        if (confirmed && context.mounted) {
                          setState(() => completing = true);
                          try {
                            await widget.onComplete();
                          } finally {
                            if (mounted) setState(() => completing = false);
                          }
                        }
                      }
                    : null,
                icon: completing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(card.isCompleted
                        ? Icons.check_circle_outline
                        : Icons.medication_outlined),
                label: Text(
                  completing
                      ? 'กำลังดำเนินการ...'
                      : card.isCompleted
                          ? 'ทานแล้ว'
                          : !connected
                              ? 'เชื่อมต่อเครื่องก่อนรับยา'
                              : card.isCurrent
                                  ? 'รับยา'
                                  : 'ไม่ใช่มื้อปัจจุบัน',
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Future<bool> _confirmMedicine(
    BuildContext context, List<DrugDose> doses) async {
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('ตรวจสอบยาก่อนทาน'),
          content: SizedBox(
            width: 340,
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                      'ยาที่เตรียมไว้ตรงกับรูปและรายการต่อไปนี้หรือไม่?'),
                  const SizedBox(height: 14),
                  ...doses.map((dose) => Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        clipBehavior: Clip.antiAlias,
                        child: Row(children: [
                          SizedBox(
                            width: 82,
                            height: 82,
                            child: dose.drug.labelImagePath == null
                                ? const ColoredBox(
                                    color: MeDisColors.primarySoft,
                                    child: Icon(
                                        Icons.image_not_supported_outlined,
                                        color: MeDisColors.subtle))
                                : localImage(dose.drug.labelImagePath!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Icon(
                                        Icons.broken_image_outlined)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(dose.drug.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                                Text('${dose.quantity} เม็ด'),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                        ]),
                      )),
                  const SizedBox(height: 8),
                  SlideToConfirm(
                      sliderKey: const Key('confirm-intake-slider'),
                      label: 'สไลด์เพื่อยืนยันการทานยา',
                      onConfirmed: () => Navigator.pop(context, true)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('ยังไม่ทาน')),
          ],
        ),
      ) ??
      false;
}

class _EmptyPlan extends StatelessWidget {
  const _EmptyPlan();
  @override
  Widget build(BuildContext context) => MeDisEmptyState(
      icon: Icons.medication_outlined,
      title: 'ยังไม่มียาในตารางวันนี้',
      message: 'เพิ่มยาประจำและเลือกมื้อทานยา เพื่อเริ่มติดตามที่นี่',
      action: OutlinedButton.icon(
          onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const DispenserScreen())),
          icon: const Icon(Icons.inventory_2_outlined),
          label: const Text('จัดการยา')));
}

class _PrnTab extends StatelessWidget {
  const _PrnTab({required this.prnSlots});
  final List<DispenserSlot> prnSlots;

  @override
  Widget build(BuildContext context) {
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        Row(children: [
          Expanded(
            child: Text(
              'ยาตามอาการในตู้ (${prnSlots.length} รายการ)',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        if (prnSlots.isEmpty) const _EmptyPrnPlan(),
        ...prnSlots.map((slot) => _PrnDrugCard(
              key: ValueKey(slot.number),
              slot: slot,
            )),
        const MeDisNotice(message: 'ใช้ยาตามคำแนะนำของแพทย์หรือเภสัชกร'),
      ],
    );
  }
}

class _EmptyPrnPlan extends StatelessWidget {
  const _EmptyPrnPlan();
  @override
  Widget build(BuildContext context) => MeDisEmptyState(
      icon: Icons.healing_outlined,
      title: 'ยังไม่มียาตามอาการในตู้จ่ายยา',
      message: 'เพิ่มยาแล้วเลือกประเภท “ทานเมื่อมีอาการ (PRN)”',
      action: OutlinedButton.icon(
          onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const DispenserScreen())),
          icon: const Icon(Icons.inventory_2_outlined),
          label: const Text('จัดการยา')));
}

class _PrnDrugCard extends StatefulWidget {
  const _PrnDrugCard({required this.slot, super.key});
  final DispenserSlot slot;

  @override
  State<_PrnDrugCard> createState() => _PrnDrugCardState();
}

class _PrnDrugCardState extends State<_PrnDrugCard> {
  bool expanded = true;
  bool dispensing = false;

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final slot = widget.slot;
    final drug = slot.drug!;
    final config = drug.prnConfig ??
        const PrnConfig(
            symptom: 'เมื่อมีอาการ',
            quantity: 1,
            minIntervalHours: 4,
            maxDosesPerDay: 4);
    final status = controller.checkPrnStatus(drug);

    final enough = slot.remaining >= config.quantity;
    final available = status.canTake && enough;
    final statusText = !enough
        ? 'ยาในช่องไม่เพียงพอ กรุณาเติมยา'
        : !status.canTake
            ? status.reason
            : 'พร้อมรับยาเมื่อมีอาการ';
    return MeDisMedicationCard(
      title: drug.name,
      subtitle: 'ช่อง ${slot.number} · คงเหลือ ${slot.remaining} เม็ด',
      icon: Icons.healing_outlined,
      expanded: expanded,
      highlighted: available && controller.connected,
      onToggle: () => setState(() => expanded = !expanded),
      status: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(available ? Icons.check_circle_outline : Icons.access_time,
            color: available ? MeDisColors.success : MeDisColors.warning,
            size: 22),
        const SizedBox(width: 8),
        Expanded(
            child: Text(statusText,
                style: TextStyle(
                    fontSize: 16,
                    color:
                        available ? MeDisColors.success : MeDisColors.warning,
                    height: 1.5))),
      ]),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: MeDisColors.primarySoft,
              borderRadius: BorderRadius.circular(MeDisRadius.input)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('ครั้งละ ${config.quantity} เม็ด',
                style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: MeDisColors.text)),
            const SizedBox(height: 6),
            Text(
                config.symptom.isEmpty
                    ? 'ทานเมื่อมีอาการ'
                    : 'เมื่อ${config.symptom}',
                style: const TextStyle(fontSize: 18, height: 1.5)),
            const Divider(height: 24),
            _PrnInstruction(
                icon: Icons.timer_outlined,
                text: 'เว้นอย่างน้อย ${config.minIntervalHours} ชั่วโมง'),
            const SizedBox(height: 8),
            _PrnInstruction(
                icon: Icons.event_available_outlined,
                text: 'ไม่เกิน ${config.maxDosesPerDay} ครั้งต่อวัน'),
          ]),
        ),
        const SizedBox(height: 8),
        Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => DrugDetailScreen(drug: drug))),
              icon: const Icon(Icons.info_outline, size: 24),
              label: const Text('ดูข้อมูลยา', style: TextStyle(fontSize: 18)),
            )),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton.icon(
            key: Key('receive-prn-${slot.number}'),
            onPressed: (controller.connected && !dispensing && available)
                ? () async {
                    final confirmed =
                        await _confirmPrnMedicine(context, drug, slot);
                    if (confirmed && context.mounted) {
                      setState(() => dispensing = true);
                      try {
                        await controller.completePrnIntake(drug);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content:
                                  Text('จ่ายยา ${drug.name} เรียบร้อยแล้ว')));
                        }
                      } catch (error) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(error
                                  .toString()
                                  .replaceFirst('Bad state: ', ''))));
                        }
                      } finally {
                        if (mounted) setState(() => dispensing = false);
                      }
                    }
                  }
                : null,
            icon: dispensing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.healing_outlined),
            label: Text(
              dispensing
                  ? 'กำลังดำเนินการ...'
                  : !controller.connected
                      ? 'เชื่อมต่อเครื่องก่อนรับยา'
                      : !enough
                          ? 'กรุณาเติมยา'
                          : status.canTake
                              ? 'รับยา'
                              : 'ยังไม่ถึงเวลารับยา',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }
}

class _PrnInstruction extends StatelessWidget {
  const _PrnInstruction({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 24, color: MeDisColors.primary),
        const SizedBox(width: 10),
        Expanded(
            child:
                Text(text, style: const TextStyle(fontSize: 16, height: 1.5))),
      ]);
}

Future<bool> _confirmPrnMedicine(
    BuildContext context, Drug drug, DispenserSlot slot) async {
  final config = drug.prnConfig ??
      const PrnConfig(
          symptom: 'เมื่อมีอาการ',
          quantity: 1,
          minIntervalHours: 4,
          maxDosesPerDay: 4);
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('ตรวจสอบยาก่อนทาน'),
          content: SizedBox(
            width: 340,
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                      'ยาที่เตรียมไว้ตรงกับรูปและรายการต่อไปนี้หรือไม่?'),
                  const SizedBox(height: 14),
                  Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    clipBehavior: Clip.antiAlias,
                    child: Row(children: [
                      SizedBox(
                        width: 82,
                        height: 82,
                        child: drug.labelImagePath == null
                            ? const ColoredBox(
                                color: MeDisColors.primarySoft,
                                child: Icon(Icons.image_not_supported_outlined,
                                    color: MeDisColors.subtle))
                            : localImage(drug.labelImagePath!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    const Icon(Icons.broken_image_outlined)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(drug.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700)),
                            Text(
                                '${config.quantity} เม็ด (ช่องที่ ${slot.number})'),
                            if (config.symptom.isNotEmpty)
                              Text('อาการ: ${config.symptom}',
                                  style: const TextStyle(
                                      color: MeDisColors.muted, fontSize: 12)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                    ]),
                  ),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '• ระบบจะเริ่มนับเวลาความปลอดภัย ${config.minIntervalHours} ชั่วโมง',
                          style: const TextStyle(
                              fontSize: 12, color: MeDisColors.muted),
                        ),
                        if (drug.notes.trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            '• คำแนะนำ: ${drug.notes.trim()}',
                            style: const TextStyle(
                                fontSize: 12, color: MeDisColors.muted),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SlideToConfirm(
                      sliderKey: const Key('confirm-intake-slider'),
                      label: 'สไลด์เพื่อยืนยันการทานยา',
                      onConfirmed: () => Navigator.pop(context, true)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('ยังไม่ทาน'),
            ),
          ],
        ),
      ) ??
      false;
}
