import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/medis_theme.dart';

import '../application/app_controller.dart';
import '../application/app_scope.dart';
import '../domain/meal_schedule.dart';
import '../domain/models.dart';
import '../widgets/local_image.dart';
import '../widgets/medication_card.dart';
import '../widgets/medis_ui.dart';
import '../widgets/pill_character.dart';
import '../widgets/slide_to_confirm.dart';
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
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            child: Column(
              children: [
                const _TodayBanner(),
                const SizedBox(height: 10),
                const _SlidingTabBar(),
              ],
            ),
          ),
          const SizedBox(height: 4),
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
        borderRadius: BorderRadius.circular(18),
        child: Stack(children: [
          Positioned.fill(
              child: Image.asset('assets/images/daily_header.png',
                  fit: BoxFit.cover, excludeFromSemantics: true)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(children: [
              Flexible(
                  flex: 5,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .96),
                        borderRadius: BorderRadius.circular(14)),
                    child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('ยาวันนี้',
                              style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: MeDisColors.text,
                                  height: 1.2)),
                          SizedBox(height: 2),
                          Text('ทานยาตรงเวลา ดูแลสุขภาพทุกวัน',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: MeDisColors.muted,
                                  height: 1.3)),
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
        height: 48,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
            color: MeDisColors.primarySoft,
            borderRadius: BorderRadius.circular(18)),
        child: TabBar(
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: Colors.transparent,
          labelPadding: const EdgeInsets.symmetric(horizontal: 4),
          indicator: BoxDecoration(
              color: MeDisColors.surface,
              borderRadius: BorderRadius.circular(14)),
          labelColor: MeDisColors.primary,
          unselectedLabelColor: MeDisColors.muted,
          labelStyle:
              const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          unselectedLabelStyle:
              const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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
        time: controller.alertSettings.timeForDose(meal.type, beforeFood: true),
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
        time:
            controller.alertSettings.timeForDose(meal.type, beforeFood: false),
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
  // 1. Prioritize current meal card if present
  if (currentMeal != null) {
    final curIncomplete = cards
        .indexWhere((c) => c.mealType == currentMeal.type && !c.isCompleted);
    if (curIncomplete != -1) return curIncomplete;

    final curIdx = cards.indexWhere((c) => c.mealType == currentMeal.type);
    if (curIdx != -1) return curIdx;
  }
  // 2. Prioritize first incomplete card
  final firstIncomplete = cards.indexWhere((c) => !c.isCompleted);
  if (firstIncomplete != -1) return firstIncomplete;

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
        ],
      );
    }

    return _CurvedMealCarousel(
      cards: cards,
      completedCount: completedCount,
      initialIndex: initialIndex,
      currentMealIndex: currentMealIndex,
      onCompleteCard: (card) async {
        try {
          await controller.completeMeal(card.mealType, doses: card.doses);
        } catch (error) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content:
                    Text(error.toString().replaceFirst('Bad state: ', ''))));
          }
        }
      },
    );
  }
}

class _CurvedMealCarousel extends StatefulWidget {
  const _CurvedMealCarousel({
    required this.cards,
    required this.completedCount,
    required this.initialIndex,
    required this.currentMealIndex,
    required this.onCompleteCard,
  });

  final List<ScheduledMealCardData> cards;
  final int completedCount;
  final int initialIndex;
  final int currentMealIndex;
  final Future<void> Function(ScheduledMealCardData card) onCompleteCard;

  @override
  State<_CurvedMealCarousel> createState() => _CurvedMealCarouselState();
}

class _CurvedMealCarouselState extends State<_CurvedMealCarousel> {
  late PageController _pageController;
  late int _currentPage;
  bool _hideCartoon = false;

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
    if (oldWidget.cards.length != widget.cards.length ||
        (oldWidget.currentMealIndex != widget.currentMealIndex &&
            widget.currentMealIndex != -1)) {
      final target = widget.initialIndex.clamp(
          0, widget.cards.isEmpty ? 0 : widget.cards.length - 1);
      _currentPage = target;
      if (_pageController.hasClients) {
        _pageController.jumpToPage(target);
      }
    } else if (_currentPage >= widget.cards.length && widget.cards.isNotEmpty) {
      _currentPage = widget.cards.length - 1;
      if (_pageController.hasClients) {
        _pageController.jumpToPage(_currentPage);
      }
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

  void _handleVerticalSwipe(DragUpdateDetails details) {
    if (details.primaryDelta == null) return;
    if (details.primaryDelta! < -6 && !_hideCartoon) {
      setState(() => _hideCartoon = true);
    } else if (details.primaryDelta! > 6 && _hideCartoon) {
      setState(() => _hideCartoon = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.cards.isEmpty) return const _EmptyPlan();

    final activeCard = widget.cards[_currentPage];

    return AnimatedBuilder(
      animation: _pageController,
      builder: (context, _) {
        MealType? morphToMeal;
        bool? morphToIsTaken;
        double morphProgress = 0.0;

        if (_pageController.hasClients &&
            _pageController.position.haveDimensions) {
          final page = (_pageController.page ?? _currentPage.toDouble())
              .clamp(0.0, (widget.cards.length - 1).toDouble());
          final diff = page - _currentPage;
          if (diff.abs() > 0.005) {
            final targetIdx =
                (diff > 0 ? _currentPage + 1 : _currentPage - 1)
                    .clamp(0, widget.cards.length - 1);
            morphToMeal = widget.cards[targetIdx].mealType;
            morphToIsTaken = widget.cards[targetIdx].isCompleted;
            morphProgress = diff.abs().clamp(0.0, 1.0);
          }
        }

        final isNight = activeCard.mealType == MealType.dinner ||
            activeCard.mealType == MealType.bedtime;
        final sceneTextColor =
            isNight ? Colors.white : const Color(0xFF2D3748);

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
          child: PillSceneBackground(
            key: const Key('full-screen-cartoon-scene-box'),
            meal: activeCard.mealType,
            isTaken: activeCard.isCompleted,
            morphToMeal: morphToMeal,
            morphToIsTaken: morphToIsTaken,
            morphProgress: morphProgress,
            borderRadius: 22.0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'วันนี้ทานแล้ว ${widget.completedCount} จาก ${widget.cards.length} มื้อ',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: sceneTextColor,
                        ),
                      ),
                      const SizedBox(height: 5),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          minHeight: 5,
                          backgroundColor: isNight
                              ? Colors.white.withValues(alpha: 0.22)
                              : Colors.black.withValues(alpha: 0.10),
                          valueColor:
                              AlwaysStoppedAnimation<Color>(activeCard.color),
                          value: widget.cards.isEmpty
                              ? 0.0
                              : widget.completedCount / widget.cards.length,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final cartoonHeight =
                          (constraints.maxHeight * 0.35).clamp(105.0, 175.0);

                      return Column(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 280),
                            curve: Curves.easeOutCubic,
                            height: _hideCartoon ? 0.0 : cartoonHeight,
                            clipBehavior: Clip.hardEdge,
                            decoration: const BoxDecoration(),
                            child: SingleChildScrollView(
                              physics: const NeverScrollableScrollPhysics(),
                              child: PillCharacterWidget(
                                key: const Key('active-meal-cartoon-stage'),
                                meal: activeCard.mealType,
                                isTaken: activeCard.isCompleted,
                                height: cartoonHeight,
                                showBackground: false,
                                morphToMeal: morphToMeal,
                                morphToIsTaken: morphToIsTaken,
                                morphProgress: morphProgress,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.translucent,
                              onVerticalDragUpdate: _handleVerticalSwipe,
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
                                      if (_pageController.hasClients &&
                                          _pageController
                                              .position.haveDimensions) {
                                        final page = _pageController.page ??
                                            _currentPage.toDouble();
                                        diff = index - page;
                                      } else {
                                        diff =
                                            (index - _currentPage).toDouble();
                                      }

                                      final absDiff =
                                          diff.abs().clamp(0.0, 2.0);
                                      final dy = math.pow(absDiff, 1.8) * 26.0;
                                      final rotation = diff * 0.055;
                                      final scale = (1.0 - absDiff * 0.08)
                                          .clamp(0.85, 1.0);
                                      final opacity = (1.0 - absDiff * 0.35)
                                          .clamp(0.45, 1.0);

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
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      child: _SingleMealCard(
                                        card: card,
                                        isCartoonHidden: _hideCartoon,
                                        onToggleCartoon: () => setState(
                                            () => _hideCartoon = !_hideCartoon),
                                        onVerticalSwipe: _handleVerticalSwipe,
                                        onComplete: () =>
                                            widget.onCompleteCard(card),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 6),
                _PageDots(
                  count: widget.cards.length,
                  currentIndex: _currentPage,
                  activeColor: isNight ? Colors.white : activeCard.color,
                  inactiveColor: isNight
                      ? Colors.white.withValues(alpha: 0.35)
                      : Colors.black.withValues(alpha: 0.20),
                  onTap: _goToPage,
                ),
                if (widget.currentMealIndex != -1) ...[
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Center(
                      child: _JumpToCurrentMealButton(
                        isAlreadyOnCurrent:
                            _currentPage == widget.currentMealIndex,
                        currentMealTitle:
                            widget.cards[widget.currentMealIndex].title,
                        accentColor:
                            widget.cards[widget.currentMealIndex].color,
                        isNight: isNight,
                        onPressed: _currentPage == widget.currentMealIndex
                            ? null
                            : () => _goToPage(widget.currentMealIndex),
                      ),
                    ),
                  ),
                ] else
                  const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _JumpToCurrentMealButton extends StatelessWidget {
  const _JumpToCurrentMealButton({
    required this.isAlreadyOnCurrent,
    required this.currentMealTitle,
    required this.accentColor,
    required this.isNight,
    required this.onPressed,
  });

  final bool isAlreadyOnCurrent;
  final String currentMealTitle;
  final Color accentColor;
  final bool isNight;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final pillBackground = isAlreadyOnCurrent
        ? (isNight
            ? Colors.white.withValues(alpha: 0.14)
            : Colors.white.withValues(alpha: 0.78))
        : Colors.white.withValues(alpha: 0.96);

    final borderColor = isAlreadyOnCurrent
        ? (isNight
            ? Colors.white.withValues(alpha: 0.28)
            : accentColor.withValues(alpha: 0.32))
        : accentColor.withValues(alpha: 0.65);

    final textColor = isAlreadyOnCurrent
        ? (isNight ? Colors.white : MeDisColors.text)
        : MeDisColors.text;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: pillBackground,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: borderColor,
          width: isAlreadyOnCurrent ? 1.2 : 1.6,
        ),
        boxShadow: [
          if (!isAlreadyOnCurrent)
            BoxShadow(
              color: accentColor.withValues(alpha: 0.30),
              blurRadius: 12,
              offset: const Offset(0, 4),
            )
          else
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const Key('jump-to-current-meal-button'),
          onTap: onPressed,
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 5, 12, 5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color.lerp(accentColor, Colors.white, 0.18)!,
                        accentColor,
                      ],
                    ),
                  ),
                  child: Icon(
                    isAlreadyOnCurrent
                        ? Icons.check_rounded
                        : Icons.near_me_rounded,
                    size: 15,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    isAlreadyOnCurrent
                        ? 'มื้อปัจจุบัน · $currentMealTitle'
                        : 'กลับไปมื้อปัจจุบัน · $currentMealTitle',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                    ),
                  ),
                ),
                if (!isAlreadyOnCurrent) ...[
                  const SizedBox(width: 6),
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      size: 13,
                      color: accentColor,
                    ),
                  ),
                ],
              ],
            ),
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
    required this.activeColor,
    required this.inactiveColor,
    required this.onTap,
  });

  final int count;
  final int currentIndex;
  final Color activeColor;
  final Color inactiveColor;
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
              color: isSelected ? activeColor : inactiveColor,
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
    required this.isCartoonHidden,
    required this.onToggleCartoon,
    required this.onVerticalSwipe,
    required this.onComplete,
  });

  final ScheduledMealCardData card;
  final bool isCartoonHidden;
  final VoidCallback onToggleCartoon;
  final GestureDragUpdateCallback onVerticalSwipe;
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

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: card.isCurrent ? card.color : MeDisColors.border,
          width: card.isCurrent ? 2.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: card.isCurrent
                ? card.color.withValues(alpha: 0.22)
                : Colors.black.withValues(alpha: 0.06),
            blurRadius: card.isCurrent ? 14 : 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragUpdate: widget.onVerticalSwipe,
            onTap: widget.onToggleCartoon,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
              decoration: BoxDecoration(
                color: card.isCurrent
                    ? card.color.withValues(alpha: 0.14)
                    : MeDisColors.primarySoft.withValues(alpha: 0.55),
                border: Border(
                  bottom: BorderSide(
                    color: card.isCurrent
                        ? card.color.withValues(alpha: 0.25)
                        : MeDisColors.border,
                    width: 1,
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: card.color.withValues(alpha: 0.18),
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
                                Icon(Icons.access_time_rounded,
                                    size: 14, color: card.color),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    '${card.time.format24Hour()} น. · ${card.totalPills} เม็ด (${card.doses.length} รายการ)',
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
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
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
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
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: card.color.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.notifications_active_outlined,
                                  size: 15, color: card.color),
                              const SizedBox(width: 4),
                              Text('มื้อนี้',
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: card.color)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: NotificationListener<ScrollUpdateNotification>(
              onNotification: (notification) {
                if (notification.scrollDelta != null) {
                  if (notification.scrollDelta! > 5 && !widget.isCartoonHidden) {
                    widget.onToggleCartoon();
                  } else if (notification.scrollDelta! < -5 &&
                      notification.metrics.pixels <= 0 &&
                      widget.isCartoonHidden) {
                    widget.onToggleCartoon();
                  }
                }
                return false;
              },
              child: ListView.separated(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                itemCount: card.doses.length,
                separatorBuilder: (_, __) => const Divider(height: 10),
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
                      padding: const EdgeInsets.symmetric(
                          vertical: 4, horizontal: 4),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: SizedBox(
                              width: 44,
                              height: 44,
                              child: dose.drug.labelImagePath == null
                                  ? Container(
                                      color: card.color.withValues(alpha: 0.14),
                                      child: Icon(
                                        Icons.medication_outlined,
                                        color: card.color,
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
                                    fontWeight: FontWeight.w700,
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
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                key: Key(card.buttonKeyName),
                style: FilledButton.styleFrom(
                  backgroundColor: card.color,
                  foregroundColor: Colors.white,
                ),
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

class _PrnTab extends StatefulWidget {
  const _PrnTab({required this.prnSlots});
  final List<DispenserSlot> prnSlots;

  @override
  State<_PrnTab> createState() => _PrnTabState();
}

class _PrnTabState extends State<_PrnTab> {
  bool _hideCartoon = false;

  void _handleVerticalSwipe(DragUpdateDetails details) {
    if (details.primaryDelta == null) return;
    if (details.primaryDelta! < -6 && !_hideCartoon) {
      setState(() => _hideCartoon = true);
    } else if (details.primaryDelta! > 6 && _hideCartoon) {
      setState(() => _hideCartoon = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final prnSlots = widget.prnSlots;
    final controller = AppScope.of(context);
    final now = DateTime.now();
    final anyPrnTakenToday = controller.intakeHistory
        .any((r) => r.isPrn && DateUtils.isSameDay(r.takenAt, now));

    int availableCount = 0;
    for (final slot in prnSlots) {
      final drug = slot.drug;
      if (drug == null) continue;
      final config = drug.prnConfig ??
          const PrnConfig(
              symptom: 'เมื่อมีอาการ',
              quantity: 1,
              minIntervalHours: 4,
              maxDosesPerDay: 4);
      final status = controller.checkPrnStatus(drug);
      if (status.canTake && slot.remaining >= config.quantity) {
        availableCount++;
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
      child: PillSceneBackground(
        key: const Key('prn-cartoon-scene-box'),
        isPrn: true,
        isTaken: anyPrnTakenToday,
        borderRadius: 22.0,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ยาตามอาการในตู้ (${prnSlots.length} รายการ)',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: MeDisColors.primaryDark,
                    ),
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      minHeight: 5,
                      backgroundColor: Colors.black.withValues(alpha: 0.08),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        MeDisColors.primary,
                      ),
                      value: prnSlots.isEmpty
                          ? 0.0
                          : availableCount / prnSlots.length,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final cartoonHeight =
                      (constraints.maxHeight * 0.25).clamp(95.0, 145.0);

                  return Column(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOutCubic,
                        height: _hideCartoon ? 0.0 : cartoonHeight,
                        clipBehavior: Clip.hardEdge,
                        decoration: const BoxDecoration(),
                        child: SingleChildScrollView(
                          physics: const NeverScrollableScrollPhysics(),
                          child: PillCharacterWidget(
                            key: const Key('active-prn-cartoon-stage'),
                            isPrn: true,
                            isTaken: anyPrnTakenToday,
                            height: cartoonHeight,
                            showBackground: false,
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 2, 12, 10),
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onVerticalDragUpdate: _handleVerticalSwipe,
                            child: Container(
                              key: const Key('prn-unified-card'),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.96),
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(
                                  color: MeDisColors.border,
                                  width: 1.0,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.06),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Column(
                                children: [
                                  GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onVerticalDragUpdate: _handleVerticalSwipe,
                                    onTap: () => setState(
                                        () => _hideCartoon = !_hideCartoon),
                                    child: Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.only(
                                          top: 6, bottom: 2),
                                      child: Center(
                                        child: Container(
                                          width: 36,
                                          height: 4,
                                          decoration: BoxDecoration(
                                            color: Colors.black
                                                .withValues(alpha: 0.15),
                                            borderRadius:
                                                BorderRadius.circular(99),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: prnSlots.isEmpty
                                        ? ListView(
                                            padding: const EdgeInsets.all(14),
                                            children: const [
                                              _EmptyPrnPlan(),
                                            ],
                                          )
                                        : NotificationListener<
                                            ScrollUpdateNotification>(
                                            onNotification: (notification) {
                                              if (notification.scrollDelta !=
                                                  null) {
                                                if (notification.scrollDelta! >
                                                        5 &&
                                                    !_hideCartoon) {
                                                  setState(() =>
                                                      _hideCartoon = true);
                                                } else if (notification
                                                            .scrollDelta! <
                                                        -5 &&
                                                    notification
                                                            .metrics.pixels <=
                                                        0 &&
                                                    _hideCartoon) {
                                                  setState(() =>
                                                      _hideCartoon = false);
                                                }
                                              }
                                              return false;
                                            },
                                            child: ListView.builder(
                                              key: const Key(
                                                  'prn-card-drug-list'),
                                              padding:
                                                  const EdgeInsets.fromLTRB(
                                                      12, 4, 12, 4),
                                              itemCount: prnSlots.length,
                                              itemBuilder: (context, index) {
                                                final slot = prnSlots[index];
                                                return _PrnDrugCard(
                                                  key: ValueKey(slot.number),
                                                  slot: slot,
                                                );
                                              },
                                            ),
                                          ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
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
      highlighted: false,
      onToggle: () => setState(() => expanded = !expanded),
      status: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(available ? Icons.check_circle_outline : Icons.access_time,
            color: available ? MeDisColors.success : MeDisColors.warning,
            size: 20),
        const SizedBox(width: 8),
        Expanded(
            child: Text(statusText,
                style: TextStyle(
                    fontSize: 15,
                    color:
                        available ? MeDisColors.success : MeDisColors.warning,
                    height: 1.4))),
      ]),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: MeDisColors.primarySoft,
              borderRadius: BorderRadius.circular(MeDisRadius.input)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('ครั้งละ ${config.quantity} เม็ด',
                style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: MeDisColors.text)),
            const SizedBox(height: 4),
            Text(
                config.symptom.isEmpty
                    ? 'ทานเมื่อมีอาการ'
                    : 'เมื่อ${config.symptom}',
                style: const TextStyle(fontSize: 16, height: 1.4)),
            const Divider(height: 16),
            _PrnInstruction(
                icon: Icons.timer_outlined,
                text: 'เว้นอย่างน้อย ${config.minIntervalHours} ชั่วโมง'),
            const SizedBox(height: 6),
            _PrnInstruction(
                icon: Icons.event_available_outlined,
                text: 'ไม่เกิน ${config.maxDosesPerDay} ครั้งต่อวัน'),
          ]),
        ),
        const SizedBox(height: 4),
        Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
              ),
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => DrugDetailScreen(drug: drug))),
              icon: const Icon(Icons.info_outline, size: 22),
              label: const Text('ดูข้อมูลยา', style: TextStyle(fontSize: 16)),
            )),
        const SizedBox(height: 4),
        SizedBox(
          width: double.infinity,
          height: 48,
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
        Icon(icon, size: 22, color: MeDisColors.primary),
        const SizedBox(width: 8),
        Expanded(
            child:
                Text(text, style: const TextStyle(fontSize: 15, height: 1.4))),
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
