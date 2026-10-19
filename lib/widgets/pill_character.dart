import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../domain/models.dart';

/// Complete interpolatable state for morphing between meal characters and scenes.
@immutable
class PillMorphState {
  final Color bodyColor;
  final Color bodyShadeColor;
  final Color bodyRimColor;
  final double rimOffsetX;
  final Color clothesColor;
  final Color clothesShadeColor;
  final Color clothesOutlineColor;
  final Color slipperColor;
  final Color darkFaceColor;
  final Color cheekColor;
  final Color floorShadowColor;
  final Color skyTop;
  final Color skyMid;
  final Color skyBottom;
  final Color groundColor;

  /// Morph weights (0.0 .. 1.0)
  final double coatOpenFactor;
  final double pajamaPantsFactor;
  final double patternOpacity;
  final double nightCapFactor;
  final double teddyBearFactor;
  final double eyeOpenness;
  final double eyelidDroop;
  final double mouthOpenness;
  final double teethFactor;
  final double sleepMouthFactor;

  /// Base arm angles in radians (0 = down, positive = raised up)
  final double leftArmRaise;
  final double rightArmRaise;

  /// Scene weights
  final double morningSceneWeight;
  final double lunchSceneWeight;
  final double dinnerSceneWeight;
  final double bedtimeSceneWeight;
  final double prnFactor;
  final Offset celestialPos;

  const PillMorphState({
    required this.bodyColor,
    required this.bodyShadeColor,
    required this.bodyRimColor,
    required this.rimOffsetX,
    required this.clothesColor,
    required this.clothesShadeColor,
    required this.clothesOutlineColor,
    required this.slipperColor,
    required this.darkFaceColor,
    required this.cheekColor,
    required this.floorShadowColor,
    required this.skyTop,
    required this.skyMid,
    required this.skyBottom,
    required this.groundColor,
    required this.coatOpenFactor,
    required this.pajamaPantsFactor,
    required this.patternOpacity,
    required this.nightCapFactor,
    required this.teddyBearFactor,
    required this.eyeOpenness,
    required this.eyelidDroop,
    required this.mouthOpenness,
    required this.teethFactor,
    required this.sleepMouthFactor,
    required this.leftArmRaise,
    required this.rightArmRaise,
    required this.morningSceneWeight,
    required this.lunchSceneWeight,
    required this.dinnerSceneWeight,
    required this.bedtimeSceneWeight,
    this.prnFactor = 0.0,
    required this.celestialPos,
  });

  bool get isDarkScene => (dinnerSceneWeight + bedtimeSceneWeight) > 0.5;

  /// Blue doctor / pharmacist pill mascot state for PRN ("ยาตามอาการ") matching app theme.
  factory PillMorphState.forPrn({required bool isTaken}) {
    return PillMorphState(
      bodyColor: const Color(0xFF64AEFA),
      bodyShadeColor: const Color(0xFF3685DC),
      bodyRimColor: const Color(0xFF1E5FA8),
      rimOffsetX: -6.5,
      clothesColor: const Color(0xFFF5FAFF),
      clothesShadeColor: const Color(0xFFC5E0FA),
      clothesOutlineColor: const Color(0xFF184B82),
      slipperColor: const Color(0xFF2463A6),
      darkFaceColor: const Color(0xFF152C4A),
      cheekColor: const Color(0xFFF58B82),
      floorShadowColor: const Color(0xFF7CAEE0),
      skyTop: const Color(0xFF96C7F8),
      skyMid: const Color(0xFFC8E3FC),
      skyBottom: const Color(0xFFEAF2FA),
      groundColor: const Color(0xFFD2E7FC),
      coatOpenFactor: 0.48,
      pajamaPantsFactor: 1.0,
      patternOpacity: 0.0,
      nightCapFactor: 0.0,
      teddyBearFactor: 0.0,
      eyeOpenness: 1.0,
      eyelidDroop: 0.0,
      mouthOpenness: isTaken ? 1.0 : 0.65,
      teethFactor: 0.85,
      sleepMouthFactor: 0.0,
      leftArmRaise: isTaken ? 2.15 : 0.85,
      rightArmRaise: 2.10,
      morningSceneWeight: 0.0,
      lunchSceneWeight: 0.0,
      dinnerSceneWeight: 0.0,
      bedtimeSceneWeight: 0.0,
      prnFactor: 1.0,
      celestialPos: const Offset(0.82, 0.13),
    );
  }

  factory PillMorphState.forMeal(MealType meal, {required bool isTaken}) {
    return switch (meal) {
      MealType.breakfast => PillMorphState(
          bodyColor: const Color(0xFFFFEE82),
          bodyShadeColor: const Color(0xFFFDD848),
          bodyRimColor: const Color(0xFFF4BE32),
          rimOffsetX: -6.5,
          clothesColor: const Color(0xFFB5E4FF),
          clothesShadeColor: const Color(0xFF84C6F0),
          clothesOutlineColor: const Color(0xFF3E739E),
          slipperColor: const Color(0xFFAEE2FF),
          darkFaceColor: const Color(0xFF4A2C1D),
          cheekColor: const Color(0xFFF99B75),
          floorShadowColor: const Color(0xFFE5B462),
          skyTop: const Color(0xFFFFDD94),
          skyMid: const Color(0xFFFFEEBD),
          skyBottom: const Color(0xFFFFF8E3),
          groundColor: const Color(0xFFFFF0C2),
          coatOpenFactor: 0.0,
          pajamaPantsFactor: 0.0,
          patternOpacity: 0.0,
          nightCapFactor: 0.0,
          teddyBearFactor: 0.0,
          eyeOpenness: 1.0,
          eyelidDroop: 0.0,
          mouthOpenness: 1.0,
          teethFactor: 0.0,
          sleepMouthFactor: 0.0,
          leftArmRaise: isTaken ? 2.1 : 0.35,
          rightArmRaise: 2.15,
          morningSceneWeight: 1.0,
          lunchSceneWeight: 0.0,
          dinnerSceneWeight: 0.0,
          bedtimeSceneWeight: 0.0,
          celestialPos: const Offset(0.18, 0.16),
        ),
      MealType.lunch => PillMorphState(
          bodyColor: const Color(0xFFFFAC68),
          bodyShadeColor: const Color(0xFFF58A3E),
          bodyRimColor: const Color(0xFFDF6D24),
          rimOffsetX: -6.5,
          clothesColor: const Color(0xFFFFFFFF),
          clothesShadeColor: const Color(0xFFD9EEF9),
          clothesOutlineColor: const Color(0xFF56829E),
          slipperColor: const Color(0xFFF68F46),
          darkFaceColor: const Color(0xFF4A2512),
          cheekColor: const Color(0xFFF27551),
          floorShadowColor: const Color(0xFF93CBE5),
          skyTop: const Color(0xFFA8E0FC),
          skyMid: const Color(0xFFD0EFFD),
          skyBottom: const Color(0xFFECFAFF),
          groundColor: const Color(0xFFDDF3FD),
          coatOpenFactor: 1.0,
          pajamaPantsFactor: 0.0,
          patternOpacity: 0.0,
          nightCapFactor: 0.0,
          teddyBearFactor: 0.0,
          eyeOpenness: 1.0,
          eyelidDroop: 0.0,
          mouthOpenness: 1.0,
          teethFactor: 1.0,
          sleepMouthFactor: 0.0,
          leftArmRaise: isTaken ? 2.1 : 1.15,
          rightArmRaise: 2.05,
          morningSceneWeight: 0.0,
          lunchSceneWeight: 1.0,
          dinnerSceneWeight: 0.0,
          bedtimeSceneWeight: 0.0,
          celestialPos: const Offset(0.82, 0.13),
        ),
      MealType.dinner => PillMorphState(
          bodyColor: const Color(0xFFA5B8EE),
          bodyShadeColor: const Color(0xFF899FDE),
          bodyRimColor: const Color(0xFF6E84C7),
          rimOffsetX: 6.5,
          clothesColor: const Color(0xFFE3BEEE),
          clothesShadeColor: const Color(0xFFC898DA),
          clothesOutlineColor: const Color(0xFF543F73),
          slipperColor: const Color(0xFFE3D0F2),
          darkFaceColor: const Color(0xFF342D57),
          cheekColor: const Color(0xFFE8829C),
          floorShadowColor: const Color(0xFF573463),
          skyTop: const Color(0xFF282554),
          skyMid: const Color(0xFF584485),
          skyBottom: const Color(0xFFB379A6),
          groundColor: const Color(0xFF9D6495),
          coatOpenFactor: 0.0,
          pajamaPantsFactor: 1.0,
          patternOpacity: 1.0,
          nightCapFactor: 0.0,
          teddyBearFactor: 0.0,
          eyeOpenness: 1.0,
          eyelidDroop: isTaken ? 0.0 : 0.92,
          mouthOpenness: isTaken ? 0.95 : 0.0,
          teethFactor: 0.0,
          sleepMouthFactor: 0.0,
          leftArmRaise: isTaken ? 2.05 : 0.48,
          rightArmRaise: isTaken ? 2.05 : 0.48,
          morningSceneWeight: 0.0,
          lunchSceneWeight: 0.0,
          dinnerSceneWeight: 1.0,
          bedtimeSceneWeight: 0.0,
          celestialPos: const Offset(0.81, 0.13),
        ),
      MealType.bedtime => PillMorphState(
          bodyColor: const Color(0xFF6173A8),
          bodyShadeColor: const Color(0xFF4E5F94),
          bodyRimColor: const Color(0xFF3B4A7A),
          rimOffsetX: 6.5,
          clothesColor: const Color(0xFF6076AD),
          clothesShadeColor: const Color(0xFF495D91),
          clothesOutlineColor: const Color(0xFF1E294A),
          slipperColor: const Color(0xFF677CB0),
          darkFaceColor: const Color(0xFF1C2442),
          cheekColor: const Color(0xFFC96B80),
          floorShadowColor: const Color(0xFF101829),
          skyTop: const Color(0xFF141E33),
          skyMid: const Color(0xFF1E2C49),
          skyBottom: const Color(0xFF2B3D63),
          groundColor: const Color(0xFF233354),
          coatOpenFactor: 0.0,
          pajamaPantsFactor: 1.0,
          patternOpacity: 0.0,
          nightCapFactor: 1.0,
          teddyBearFactor: 1.0,
          eyeOpenness: isTaken ? 1.0 : 0.0,
          eyelidDroop: 0.0,
          mouthOpenness: isTaken ? 0.9 : 0.0,
          teethFactor: 0.0,
          sleepMouthFactor: isTaken ? 0.0 : 1.0,
          leftArmRaise: isTaken ? 1.95 : 0.35,
          rightArmRaise: 0.65,
          morningSceneWeight: 0.0,
          lunchSceneWeight: 0.0,
          dinnerSceneWeight: 0.0,
          bedtimeSceneWeight: 1.0,
          celestialPos: const Offset(0.79, 0.13),
        ),
    };
  }

  static PillMorphState lerp(PillMorphState a, PillMorphState b, double t) {
    final clamped = t.clamp(0.0, 1.0);
    return PillMorphState(
      bodyColor: Color.lerp(a.bodyColor, b.bodyColor, clamped)!,
      bodyShadeColor: Color.lerp(a.bodyShadeColor, b.bodyShadeColor, clamped)!,
      bodyRimColor: Color.lerp(a.bodyRimColor, b.bodyRimColor, clamped)!,
      rimOffsetX: ui.lerpDouble(a.rimOffsetX, b.rimOffsetX, clamped)!,
      clothesColor: Color.lerp(a.clothesColor, b.clothesColor, clamped)!,
      clothesShadeColor:
          Color.lerp(a.clothesShadeColor, b.clothesShadeColor, clamped)!,
      clothesOutlineColor:
          Color.lerp(a.clothesOutlineColor, b.clothesOutlineColor, clamped)!,
      slipperColor: Color.lerp(a.slipperColor, b.slipperColor, clamped)!,
      darkFaceColor: Color.lerp(a.darkFaceColor, b.darkFaceColor, clamped)!,
      cheekColor: Color.lerp(a.cheekColor, b.cheekColor, clamped)!,
      floorShadowColor:
          Color.lerp(a.floorShadowColor, b.floorShadowColor, clamped)!,
      skyTop: Color.lerp(a.skyTop, b.skyTop, clamped)!,
      skyMid: Color.lerp(a.skyMid, b.skyMid, clamped)!,
      skyBottom: Color.lerp(a.skyBottom, b.skyBottom, clamped)!,
      groundColor: Color.lerp(a.groundColor, b.groundColor, clamped)!,
      coatOpenFactor:
          ui.lerpDouble(a.coatOpenFactor, b.coatOpenFactor, clamped)!,
      pajamaPantsFactor:
          ui.lerpDouble(a.pajamaPantsFactor, b.pajamaPantsFactor, clamped)!,
      patternOpacity:
          ui.lerpDouble(a.patternOpacity, b.patternOpacity, clamped)!,
      nightCapFactor:
          ui.lerpDouble(a.nightCapFactor, b.nightCapFactor, clamped)!,
      teddyBearFactor:
          ui.lerpDouble(a.teddyBearFactor, b.teddyBearFactor, clamped)!,
      eyeOpenness: ui.lerpDouble(a.eyeOpenness, b.eyeOpenness, clamped)!,
      eyelidDroop: ui.lerpDouble(a.eyelidDroop, b.eyelidDroop, clamped)!,
      mouthOpenness: ui.lerpDouble(a.mouthOpenness, b.mouthOpenness, clamped)!,
      teethFactor: ui.lerpDouble(a.teethFactor, b.teethFactor, clamped)!,
      sleepMouthFactor:
          ui.lerpDouble(a.sleepMouthFactor, b.sleepMouthFactor, clamped)!,
      leftArmRaise: ui.lerpDouble(a.leftArmRaise, b.leftArmRaise, clamped)!,
      rightArmRaise: ui.lerpDouble(a.rightArmRaise, b.rightArmRaise, clamped)!,
      morningSceneWeight:
          ui.lerpDouble(a.morningSceneWeight, b.morningSceneWeight, clamped)!,
      lunchSceneWeight:
          ui.lerpDouble(a.lunchSceneWeight, b.lunchSceneWeight, clamped)!,
      dinnerSceneWeight:
          ui.lerpDouble(a.dinnerSceneWeight, b.dinnerSceneWeight, clamped)!,
      bedtimeSceneWeight:
          ui.lerpDouble(a.bedtimeSceneWeight, b.bedtimeSceneWeight, clamped)!,
      prnFactor: ui.lerpDouble(a.prnFactor, b.prnFactor, clamped)!,
      celestialPos: Offset.lerp(a.celestialPos, b.celestialPos, clamped)!,
    );
  }
}

/// Full-screen / full-container morphing scenic background that wraps both
/// the cartoon mascot and the medication cards inside one unified box.
class PillSceneBackground extends StatefulWidget {
  final MealType meal;
  final bool isTaken;
  final bool isPrn;
  final MealType? morphToMeal;
  final bool? morphToIsTaken;
  final double morphProgress;
  final double borderRadius;
  final Widget child;

  const PillSceneBackground({
    super.key,
    this.meal = MealType.breakfast,
    required this.isTaken,
    required this.child,
    this.isPrn = false,
    this.morphToMeal,
    this.morphToIsTaken,
    this.morphProgress = 0.0,
    this.borderRadius = 26.0,
  });

  @override
  State<PillSceneBackground> createState() => _PillSceneBackgroundState();
}

class _PillSceneBackgroundState extends State<PillSceneBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _morphController;
  late PillMorphState _fromState;
  late PillMorphState _targetState;

  PillMorphState _stateForWidget() {
    if (widget.isPrn) {
      return PillMorphState.forPrn(isTaken: widget.isTaken);
    }
    return PillMorphState.forMeal(widget.meal, isTaken: widget.isTaken);
  }

  @override
  void initState() {
    super.initState();
    _fromState = _stateForWidget();
    _targetState = _fromState;
    _morphController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
      value: 1.0,
    );
  }

  PillMorphState _computeCurrentState() {
    final curved = Curves.easeInOutCubic.transform(_morphController.value);
    final baseState = PillMorphState.lerp(_fromState, _targetState, curved);
    if (!widget.isPrn &&
        widget.morphToMeal != null &&
        widget.morphProgress > 0.0) {
      final swipeTarget = PillMorphState.forMeal(
        widget.morphToMeal!,
        isTaken: widget.morphToIsTaken ?? widget.isTaken,
      );
      return PillMorphState.lerp(
        baseState,
        swipeTarget,
        Curves.easeInOutCubic.transform(widget.morphProgress.clamp(0.0, 1.0)),
      );
    }
    return baseState;
  }

  @override
  void didUpdateWidget(covariant PillSceneBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.meal != widget.meal ||
        oldWidget.isTaken != widget.isTaken ||
        oldWidget.isPrn != widget.isPrn) {
      _fromState = _computeCurrentState();
      _targetState = _stateForWidget();
      _morphController.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _morphController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _morphController,
      builder: (context, _) {
        final state = _computeCurrentState();
        return CustomPaint(
          painter: PillScenicBackdropPainter(
            state: state,
            borderRadius: widget.borderRadius,
          ),
          child: widget.child,
        );
      },
    );
  }
}

/// Paints the full-bleed sky gradient, sun, clouds, crescent moon, stars, and hills.
class PillScenicBackdropPainter extends CustomPainter {
  final PillMorphState state;
  final double borderRadius;
  final double phase;

  const PillScenicBackdropPainter({
    required this.state,
    this.borderRadius = 26.0,
    this.phase = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final bgRect = Offset.zero & size;
    final bgRRect =
        RRect.fromRectAndRadius(bgRect, Radius.circular(borderRadius));

    canvas.save();
    canvas.clipRRect(bgRRect);

    // 1. Sky Gradient
    final skyPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [state.skyTop, state.skyMid, state.skyBottom],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(bgRect);
    canvas.drawRect(bgRect, skyPaint);

    final w = size.width;
    final h = size.height;

    // 2. Soft Wavy Horizon Hills behind character & card
    final baseHillColor = Color.lerp(
      const Color(0xFFFFF5D6).withValues(alpha: 0.65),
      const Color(0xFF23204A).withValues(alpha: 0.50),
      (state.dinnerSceneWeight + state.bedtimeSceneWeight).clamp(0.0, 1.0),
    )!;
    final hillColor = Color.lerp(
      baseHillColor,
      const Color(0xFFB5D8F8).withValues(alpha: 0.72),
      state.prnFactor.clamp(0.0, 1.0),
    )!;
    final hillPath = Path()
      ..moveTo(0, h * 0.28)
      ..quadraticBezierTo(w * 0.28, h * 0.20, w * 0.58, h * 0.27)
      ..quadraticBezierTo(w * 0.84, h * 0.33, w, h * 0.24)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(hillPath, Paint()..color = hillColor);

    // 3. Lower Ground Glow
    final lowerWavePath = Path()
      ..moveTo(0, h * 0.44)
      ..quadraticBezierTo(w * 0.5, h * 0.38, w, h * 0.44)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(
      lowerWavePath,
      Paint()..color = state.groundColor.withValues(alpha: 0.65),
    );

    final celestialCenter = Offset(
      w * state.celestialPos.dx,
      h * state.celestialPos.dy,
    );

    // 4. Morning Rising Sun & Rays
    if (state.morningSceneWeight > 0.01) {
      final alpha = state.morningSceneWeight.clamp(0.0, 1.0);
      const sunRadius = 26.0;
      canvas.drawCircle(
        celestialCenter,
        sunRadius + 7,
        Paint()..color = const Color(0xFFFFE57F).withValues(alpha: 0.45 * alpha),
      );
      canvas.drawCircle(
        celestialCenter,
        sunRadius,
        Paint()..color = const Color(0xFFFFD54F).withValues(alpha: alpha),
      );

      final rayPaint = Paint()
        ..color = const Color(0xFFFFCA28).withValues(alpha: alpha)
        ..strokeWidth = 3.2
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 7; i++) {
        final angle = math.pi + (i * math.pi / 6.0) + phase * 0.04;
        final p1 = Offset(
          celestialCenter.dx + math.cos(angle) * (sunRadius + 6),
          celestialCenter.dy + math.sin(angle) * (sunRadius + 6),
        );
        final p2 = Offset(
          celestialCenter.dx + math.cos(angle) * (sunRadius + 14),
          celestialCenter.dy + math.sin(angle) * (sunRadius + 14),
        );
        canvas.drawLine(p1, p2, rayPaint);
      }
    }

    // 5. Lunch Sun & Puffy White Clouds
    if (state.lunchSceneWeight > 0.01) {
      final alpha = state.lunchSceneWeight.clamp(0.0, 1.0);
      canvas.drawCircle(
        celestialCenter,
        32,
        Paint()..color = const Color(0xFFFFF9C4).withValues(alpha: 0.55 * alpha),
      );
      canvas.drawCircle(
        celestialCenter,
        23,
        Paint()..color = const Color(0xFFFFF176).withValues(alpha: alpha),
      );
      _drawPuffyCloud(
          canvas, Offset(w * 0.16 + phase * 4, h * 0.12), 1.0, alpha);
      _drawPuffyCloud(
          canvas, Offset(w * 0.84 - phase * 3, h * 0.22), 0.88, alpha);
      _drawPuffyCloud(
          canvas, Offset(w * 0.13 + phase * 2, h * 0.26), 0.75, alpha);
    }

    // 5b. PRN App-Blue Caregiver Scene (Warm Sun, Clouds & Floating Blue Medical Crosses)
    if (state.prnFactor > 0.01) {
      final alpha = state.prnFactor.clamp(0.0, 1.0);
      canvas.drawCircle(
        celestialCenter,
        30,
        Paint()..color = const Color(0xFFEAF2FA).withValues(alpha: 0.65 * alpha),
      );
      canvas.drawCircle(
        celestialCenter,
        21,
        Paint()..color = const Color(0xFFFFF394).withValues(alpha: alpha),
      );
      _drawPuffyCloud(
          canvas, Offset(w * 0.16 + phase * 3, h * 0.11), 0.95, alpha);
      _drawPuffyCloud(
          canvas, Offset(w * 0.85 - phase * 2.5, h * 0.23), 0.82, alpha);
      _drawMedicalCrossBadge(
        canvas,
        Offset(w * 0.15, h * 0.23 + phase * 2),
        7.5,
        const Color(0xFF2463A6).withValues(alpha: 0.50 * alpha),
      );
      _drawMedicalCrossBadge(
        canvas,
        Offset(w * 0.82, h * 0.17 - phase * 2),
        6.0,
        const Color(0xFF2463A6).withValues(alpha: 0.42 * alpha),
      );
    }

    // 6. Dinner & Bedtime Crescent Moon, Stars & Floating Zzz
    final moonWeight =
        (state.dinnerSceneWeight + state.bedtimeSceneWeight).clamp(0.0, 1.0);
    if (moonWeight > 0.01) {
      final moonColor = Color.lerp(
        const Color(0xFFFFE074),
        const Color(0xFFF5F2C8),
        state.bedtimeSceneWeight.clamp(0.0, 1.0),
      )!
          .withValues(alpha: moonWeight);
      _drawCrescentMoon(
        canvas,
        center: celestialCenter,
        radius: 23,
        color: moonColor,
        sleepingAlpha: state.bedtimeSceneWeight.clamp(0.0, 1.0),
      );

      final starPaint = Paint()
        ..color = const Color(0xFFFFE57F).withValues(alpha: moonWeight);
      _drawFivePointStar(canvas, Offset(w * 0.14, h * 0.11), 7.5, starPaint);
      _drawFivePointStar(canvas, Offset(w * 0.87, h * 0.23), 6.5, starPaint);
      _drawFivePointStar(canvas, Offset(w * 0.11, h * 0.24), 5.5, starPaint);
      canvas.drawCircle(Offset(w * 0.26, h * 0.08), 2.2, starPaint);
      canvas.drawCircle(Offset(w * 0.68, h * 0.09), 2.0, starPaint);

      if (state.bedtimeSceneWeight > 0.05) {
        final zAlpha = state.bedtimeSceneWeight.clamp(0.0, 1.0);
        final floatY = phase * 3.0;
        _drawZzz(
          canvas,
          Offset(celestialCenter.dx + 25, celestialCenter.dy - 14 + floatY),
          7,
          const Color(0xFFB3C5E6).withValues(alpha: zAlpha),
        );
        _drawZzz(
          canvas,
          Offset(celestialCenter.dx + 37, celestialCenter.dy - 24 - floatY),
          9.5,
          const Color(0xFFD6E4FF).withValues(alpha: zAlpha),
        );
      }
    }

    // 7. Ambient Twinkling Sparkles
    final sparklePaint = Paint()..color = Colors.white.withValues(alpha: 0.85);
    _drawFourPointSparkle(canvas, Offset(w * 0.82, h * 0.10), 6.5, sparklePaint);
    _drawFourPointSparkle(canvas, Offset(w * 0.15, h * 0.21), 5.5, sparklePaint);

    canvas.restore();
  }

  static void _drawMedicalCrossBadge(
      Canvas canvas, Offset center, double size, Color color) {
    final paint = Paint()..color = color;
    final thickness = size * 0.42;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: size * 2, height: thickness * 2),
        Radius.circular(thickness * 0.45),
      ),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: center, width: thickness * 2, height: size * 2),
        Radius.circular(thickness * 0.45),
      ),
      paint,
    );
  }

  static void _drawPuffyCloud(
      Canvas canvas, Offset center, double scale, double alpha) {
    final paint = Paint()..color = Colors.white.withValues(alpha: 0.92 * alpha);
    final path = Path()
      ..addOval(Rect.fromCenter(
          center: Offset(center.dx - 14 * scale, center.dy + 4 * scale),
          width: 24 * scale,
          height: 18 * scale))
      ..addOval(Rect.fromCenter(
          center: Offset(center.dx, center.dy - 2 * scale),
          width: 28 * scale,
          height: 24 * scale))
      ..addOval(Rect.fromCenter(
          center: Offset(center.dx + 15 * scale, center.dy + 4 * scale),
          width: 22 * scale,
          height: 17 * scale))
      ..addRRect(RRect.fromRectAndRadius(
          Rect.fromCenter(
              center: Offset(center.dx, center.dy + 6 * scale),
              width: 44 * scale,
              height: 14 * scale),
          Radius.circular(7 * scale)));
    canvas.drawPath(path, paint);
  }

  static void _drawCrescentMoon(
    Canvas canvas, {
    required Offset center,
    required double radius,
    required Color color,
    required double sleepingAlpha,
  }) {
    final outer = Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius));
    final cutout = Path()
      ..addOval(Rect.fromCircle(
          center: Offset(center.dx + radius * 0.48, center.dy - radius * 0.22),
          radius: radius * 0.82));
    final moonPath = Path.combine(PathOperation.difference, outer, cutout);
    canvas.drawPath(moonPath, Paint()..color = color);

    if (sleepingAlpha > 0.05) {
      final eyePaint = Paint()
        ..color = const Color(0xFF434A5E).withValues(alpha: sleepingAlpha)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      final eyePath = Path()
        ..moveTo(center.dx - 11, center.dy + 2)
        ..quadraticBezierTo(
            center.dx - 7, center.dy + 6, center.dx - 3, center.dy + 2);
      canvas.drawPath(eyePath, eyePaint);
    }
  }

  static void _drawZzz(
      Canvas canvas, Offset topLeft, double size, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(topLeft.dx, topLeft.dy)
      ..lineTo(topLeft.dx + size, topLeft.dy)
      ..lineTo(topLeft.dx, topLeft.dy + size)
      ..lineTo(topLeft.dx + size, topLeft.dy + size);
    canvas.drawPath(path, paint);
  }

  static void _drawFourPointSparkle(
      Canvas canvas, Offset offset, double r, Paint paint) {
    if (r <= 1) return;
    final path = Path()
      ..moveTo(offset.dx, offset.dy - r)
      ..quadraticBezierTo(offset.dx, offset.dy, offset.dx + r, offset.dy)
      ..quadraticBezierTo(offset.dx, offset.dy, offset.dx, offset.dy + r)
      ..quadraticBezierTo(offset.dx, offset.dy, offset.dx - r, offset.dy)
      ..quadraticBezierTo(offset.dx, offset.dy, offset.dx, offset.dy - r)
      ..close();
    canvas.drawPath(path, paint);
  }

  static void _drawFivePointStar(
      Canvas canvas, Offset center, double outerRadius, Paint paint) {
    final innerRadius = outerRadius * 0.45;
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final r = i.isEven ? outerRadius : innerRadius;
      final angle = -math.pi / 2 + i * (math.pi / 5);
      final pt = Offset(
        center.dx + math.cos(angle) * r,
        center.dy + math.sin(angle) * r,
      );
      if (i == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant PillScenicBackdropPainter oldDelegate) {
    return oldDelegate.state != state ||
        oldDelegate.borderRadius != borderRadius ||
        oldDelegate.phase != phase;
  }
}

/// Animated vector cartoon pill mascot with morphing scene transitions
/// and articulated arm/leg movement.
class PillCharacterWidget extends StatefulWidget {
  final MealType meal;
  final bool isTaken;
  final bool isPrn;
  final double height;
  final bool? animate;
  final bool showBackground;

  /// Optional target meal and morph progress (0.0 .. 1.0) for live swipe morphing.
  final MealType? morphToMeal;
  final bool? morphToIsTaken;
  final double morphProgress;

  const PillCharacterWidget({
    super.key,
    this.meal = MealType.breakfast,
    required this.isTaken,
    this.isPrn = false,
    this.height = 165,
    this.animate,
    this.showBackground = true,
    this.morphToMeal,
    this.morphToIsTaken,
    this.morphProgress = 0.0,
  });

  @override
  State<PillCharacterWidget> createState() => _PillCharacterWidgetState();
}

class _PillCharacterWidgetState extends State<PillCharacterWidget>
    with TickerProviderStateMixin {
  static const _takenLoopDuration = Duration(milliseconds: 620);
  static const _idleLoopDuration = Duration(milliseconds: 1150);
  static const _morphDuration = Duration(milliseconds: 520);

  late AnimationController _loopController;
  late AnimationController _morphController;

  late PillMorphState _fromState;
  late PillMorphState _targetState;

  bool get _shouldRepeat {
    if (widget.animate != null) return widget.animate!;
    final bindingName = WidgetsBinding.instance.runtimeType.toString();
    return !bindingName.contains('TestWidgetsFlutterBinding');
  }

  PillMorphState _stateForWidget() {
    if (widget.isPrn) {
      return PillMorphState.forPrn(isTaken: widget.isTaken);
    }
    return PillMorphState.forMeal(widget.meal, isTaken: widget.isTaken);
  }

  @override
  void initState() {
    super.initState();
    _fromState = _stateForWidget();
    _targetState = _fromState;

    _loopController = AnimationController(
      vsync: this,
      duration: widget.isTaken ? _takenLoopDuration : _idleLoopDuration,
    );
    _morphController = AnimationController(
      vsync: this,
      duration: _morphDuration,
      value: 1.0,
    );

    _startOrSettleLoop();
  }

  void _startOrSettleLoop() {
    if (_shouldRepeat) {
      _loopController.repeat(reverse: true);
    } else {
      _loopController.value = 0.5;
    }
  }

  PillMorphState _computeCurrentMorphState() {
    final curvedMorph =
        Curves.easeInOutCubic.transform(_morphController.value);
    final baseState =
        PillMorphState.lerp(_fromState, _targetState, curvedMorph);

    if (!widget.isPrn &&
        widget.morphToMeal != null &&
        widget.morphProgress > 0.0) {
      final swipeTarget = PillMorphState.forMeal(
        widget.morphToMeal!,
        isTaken: widget.morphToIsTaken ?? widget.isTaken,
      );
      return PillMorphState.lerp(
        baseState,
        swipeTarget,
        Curves.easeInOutCubic.transform(widget.morphProgress.clamp(0.0, 1.0)),
      );
    }
    return baseState;
  }

  @override
  void didUpdateWidget(covariant PillCharacterWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.meal != widget.meal ||
        oldWidget.isTaken != widget.isTaken ||
        oldWidget.isPrn != widget.isPrn) {
      _fromState = _computeCurrentMorphState();
      _targetState = _stateForWidget();
      _morphController.forward(from: 0.0);
    }

    if (oldWidget.isTaken != widget.isTaken ||
        oldWidget.animate != widget.animate) {
      _loopController.duration =
          widget.isTaken ? _takenLoopDuration : _idleLoopDuration;
      _loopController.reset();
      _startOrSettleLoop();
    }
  }

  @override
  void dispose() {
    _loopController.dispose();
    _morphController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: AnimatedBuilder(
        animation: Listenable.merge([_loopController, _morphController]),
        builder: (context, _) {
          final state = _computeCurrentMorphState();
          final t = _loopController.value;
          final wave = math.sin(t * math.pi * 2);
          final bounceCurve = Curves.easeInOutSine.transform(t);

          final bounceOffset =
              widget.isTaken ? -18.0 * bounceCurve : -8.5 * bounceCurve;
          final squash = widget.isTaken
              ? ui.lerpDouble(0.94, 1.06, bounceCurve)!
              : ui.lerpDouble(0.97, 1.03, bounceCurve)!;
          final tilt = (widget.isTaken ? 0.065 : 0.035) * wave;

          return SizedBox.expand(
            child: CustomPaint(
              painter: PillVectorPainter(
                state: state,
                isTaken: widget.isTaken,
                animValue: t,
                limbPhase: wave,
                bounceOffset: bounceOffset,
                squash: squash,
                tilt: tilt,
                showBackground: widget.showBackground,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Vector painter with borderless 3D pill body, strictly-clipped clothing shadows,
/// refined Evening dreamy eyes, articulated arms/legs, and morphing transitions.
class PillVectorPainter extends CustomPainter {
  final PillMorphState state;
  final bool isTaken;
  final double animValue;
  final double limbPhase;
  final double bounceOffset;
  final double squash;
  final double tilt;
  final bool showBackground;

  const PillVectorPainter({
    required this.state,
    required this.isTaken,
    required this.animValue,
    required this.limbPhase,
    this.bounceOffset = 0.0,
    this.squash = 1.0,
    this.tilt = 0.0,
    this.showBackground = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    if (showBackground) {
      PillScenicBackdropPainter(
        state: state,
        borderRadius: 22.0,
        phase: limbPhase,
      ).paint(canvas, size);
    }

    final charScale = (size.height / 205.0).clamp(0.45, 1.30);
    final stageCenter = Offset(size.width * 0.5, size.height * 0.52);

    canvas.save();
    canvas.translate(stageCenter.dx, stageCenter.dy);
    canvas.scale(charScale, charScale);

    const center = Offset.zero;
    const radius = 58.0;

    // 1. Dynamic Floor Shadow beneath feet
    final shadowScale =
        (1.0 - (bounceOffset.abs() / 52.0)).clamp(0.62, 1.0);
    canvas.drawOval(
      Rect.fromCenter(
        center: const Offset(0, 84),
        width: 138 * shadowScale,
        height: 17 * shadowScale,
      ),
      Paint()..color = state.floorShadowColor.withValues(alpha: 0.72),
    );

    // 2. Transform character body with bounce, tilt, and squash/stretch
    canvas.save();
    canvas.translate(0, bounceOffset);
    canvas.rotate(tilt);
    canvas.scale(2.0 - squash, squash);

    _drawArticulatedLegs(canvas, center);
    _drawBackArms(canvas, center);
    _drawBorderlessPillBody(canvas, center, radius);
    _drawDetailedOutfit(canvas, center, radius);
    _drawFrontArmsAndTeddy(canvas, center);
    _drawMorphingHeadgear(canvas, center, radius);
    _drawFacialFeatures(canvas, center);

    if (isTaken) {
      final starPaint = Paint()..color = const Color(0xFFFFD700);
      PillScenicBackdropPainter._drawFourPointSparkle(
        canvas,
        const Offset(-90, -38),
        9 + 4 * animValue,
        starPaint,
      );
      PillScenicBackdropPainter._drawFourPointSparkle(
        canvas,
        const Offset(92, -34),
        9 + 4 * (1 - animValue),
        starPaint,
      );
    }

    canvas.restore();
    canvas.restore();
  }

  // ---------------------------------------------------------------------------
  // 1. Articulated Legs, Pajama Pants & Slippers
  //    (Bare legs = NO border; Pajama pants & slippers = WITH border & clipped shading)
  // ---------------------------------------------------------------------------
  void _drawArticulatedLegs(Canvas canvas, Offset center) {
    final swingAmp = isTaken ? 0.28 : 0.16;
    final liftAmp = isTaken ? 6.0 : 3.5;

    for (final side in [-1.0, 1.0]) {
      final hip = Offset(center.dx + side * 20.0, center.dy + 52.0);
      final legAngle = side * limbPhase * swingAmp;
      final legLift =
          (side * limbPhase > 0) ? -liftAmp * (side * limbPhase) : 0.0;

      canvas.save();
      canvas.translate(hip.dx, hip.dy + legLift);
      canvas.rotate(legAngle);

      // Bare Pill Leg (BORDERLESS)
      final bareLegRect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: const Offset(0, 15), width: 12, height: 34),
        const Radius.circular(6),
      );
      canvas.drawRRect(bareLegRect, Paint()..color = state.bodyShadeColor);

      // Pajama Trousers (with strictly clipped inner shadows & pattern)
      if (state.pajamaPantsFactor > 0.01) {
        final pAlpha = state.pajamaPantsFactor.clamp(0.0, 1.0);
        final pantRect = RRect.fromRectAndRadius(
          Rect.fromCenter(center: const Offset(0, 14), width: 24, height: 28),
          const Radius.circular(6),
        );

        canvas.save();
        canvas.clipRRect(pantRect);
        canvas.drawRRect(
          pantRect,
          Paint()..color = state.clothesShadeColor.withValues(alpha: pAlpha),
        );
        // Inner side shadow fitted strictly inside pantRect
        canvas.drawRect(
          Rect.fromLTWH(side < 0 ? -12 : 5, 0, 7, 28),
          Paint()
            ..color = Color.lerp(state.clothesShadeColor, Colors.black, 0.12)!
                .withValues(alpha: pAlpha * 0.6),
        );
        canvas.drawLine(
          const Offset(-12, 23),
          const Offset(12, 23),
          Paint()
            ..color = state.clothesOutlineColor.withValues(alpha: pAlpha * 0.65)
            ..strokeWidth = 1.6,
        );
        if (state.patternOpacity > 0.05) {
          final dotPaint = Paint()
            ..color = const Color(0xFFAA7BC2)
                .withValues(alpha: 0.75 * state.patternOpacity * pAlpha);
          canvas.drawCircle(const Offset(-4, 12), 2.2, dotPaint);
          canvas.drawCircle(const Offset(5, 17), 2.2, dotPaint);
        }
        canvas.restore();

        canvas.drawRRect(
          pantRect,
          Paint()
            ..color = state.clothesOutlineColor.withValues(alpha: pAlpha)
            ..strokeWidth = 2.2
            ..style = PaintingStyle.stroke,
        );
      }

      // Slippers / Footwear
      canvas.save();
      canvas.translate(side * 3.0, 31.0);
      canvas.rotate(-legAngle * 0.45);
      final shoeRect =
          Rect.fromCenter(center: Offset.zero, width: 27, height: 14);
      final shoePath = Path()..addOval(shoeRect);

      canvas.save();
      canvas.clipPath(shoePath);
      canvas.drawPath(shoePath, Paint()..color = state.slipperColor);
      canvas.drawOval(
        Rect.fromCenter(center: const Offset(0, 1.5), width: 16, height: 7.5),
        Paint()..color = Color.lerp(state.slipperColor, Colors.black, 0.14)!,
      );
      canvas.restore();

      final slipperOutlineAlpha = (1.0 - state.coatOpenFactor).clamp(0.0, 1.0);
      if (slipperOutlineAlpha > 0.05) {
        canvas.drawOval(
          shoeRect,
          Paint()
            ..color =
                state.clothesOutlineColor.withValues(alpha: slipperOutlineAlpha)
            ..strokeWidth = 2.1
            ..style = PaintingStyle.stroke,
        );
      }
      canvas.restore();

      canvas.restore();
    }
  }

  // ---------------------------------------------------------------------------
  // 2. Articulated Arms & Waving Hands
  //    (Hands = NO border; Sleeves = WITH border & strictly clipped cuff shading)
  // ---------------------------------------------------------------------------
  void _drawBackArms(Canvas canvas, Offset center) {
    final waveAmp = isTaken ? 0.34 : 0.24;

    final leftShoulder = Offset(center.dx - 45, center.dy + 20);
    final leftWave = limbPhase * waveAmp;
    _drawPivotingArm(
      canvas,
      shoulder: leftShoulder,
      isLeft: true,
      raiseAngle: state.leftArmRaise + leftWave,
    );

    if (state.teddyBearFactor < 0.85) {
      final rightShoulder = Offset(center.dx + 45, center.dy + 19);
      final rightWave = -limbPhase * (waveAmp * 1.15);
      _drawPivotingArm(
        canvas,
        shoulder: rightShoulder,
        isLeft: false,
        raiseAngle: state.rightArmRaise + rightWave,
      );
    }
  }

  void _drawPivotingArm(
    Canvas canvas, {
    required Offset shoulder,
    required bool isLeft,
    required double raiseAngle,
  }) {
    final dir = isLeft ? -1.0 : 1.0;
    final baseAngle = isLeft
        ? (math.pi * 0.68 + raiseAngle * 0.55)
        : (math.pi * 0.32 - raiseAngle * 0.55);

    const armLength = 34.0;
    final handCenter = Offset(
      shoulder.dx + math.cos(baseAngle) * armLength,
      shoulder.dy + math.sin(baseAngle) * armLength,
    );
    final cuffCenter = Offset.lerp(shoulder, handCenter, 0.76)!;

    // Borderless 3D Pill Hand & Thumb
    canvas.drawCircle(handCenter, 9.2, Paint()..color = state.bodyShadeColor);
    canvas.drawCircle(
      handCenter + Offset(-dir * 1.0, -1.0),
      8.4,
      Paint()..color = state.bodyColor,
    );
    final thumbOffset = Offset(
      handCenter.dx + math.cos(baseAngle - dir * 1.2) * 7.5,
      handCenter.dy + math.sin(baseAngle - dir * 1.2) * 7.5,
    );
    canvas.drawCircle(thumbOffset, 4.2, Paint()..color = state.bodyColor);

    // Outlined Sleeve with shading strictly clipped inside sleevePath
    final perpAngle = baseAngle + math.pi / 2;
    final pNeck = Offset(
      shoulder.dx + math.cos(perpAngle) * 8.5,
      shoulder.dy + math.sin(perpAngle) * 8.5,
    );
    final pArmpit = Offset(
      shoulder.dx - math.cos(perpAngle) * 8.5,
      shoulder.dy - math.sin(perpAngle) * 8.5,
    );
    final pCuffTop = Offset(
      cuffCenter.dx + math.cos(perpAngle) * 9.5,
      cuffCenter.dy + math.sin(perpAngle) * 9.5,
    );
    final pCuffBot = Offset(
      cuffCenter.dx - math.cos(perpAngle) * 9.5,
      cuffCenter.dy - math.sin(perpAngle) * 9.5,
    );

    final sleevePath = Path()
      ..moveTo(pNeck.dx, pNeck.dy)
      ..lineTo(pCuffTop.dx, pCuffTop.dy)
      ..lineTo(pCuffBot.dx, pCuffBot.dy)
      ..lineTo(pArmpit.dx, pArmpit.dy)
      ..close();

    final cuffInnerTop = Offset.lerp(pNeck, pCuffTop, 0.76)!;
    final cuffInnerBot = Offset.lerp(pArmpit, pCuffBot, 0.76)!;
    final cuffBandPath = Path()
      ..moveTo(cuffInnerTop.dx, cuffInnerTop.dy)
      ..lineTo(pCuffTop.dx, pCuffTop.dy)
      ..lineTo(pCuffBot.dx, pCuffBot.dy)
      ..lineTo(cuffInnerBot.dx, cuffInnerBot.dy)
      ..close();

    // Clip all sleeve fills and shadows strictly inside sleevePath
    canvas.save();
    canvas.clipPath(sleevePath);
    canvas.drawPath(sleevePath, Paint()..color = state.clothesColor);
    canvas.drawPath(cuffBandPath, Paint()..color = state.clothesShadeColor);
    canvas.restore();

    final sleeveOutline = Paint()
      ..color = state.clothesOutlineColor
      ..strokeWidth = 2.2
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(sleevePath, sleeveOutline);
    canvas.drawLine(cuffInnerTop, cuffInnerBot, sleeveOutline);
  }

  // ---------------------------------------------------------------------------
  // 3. Borderless 3D Pill Body (ตัวการ์ตูนไม่ต้องมีขอบ และเงาไม่ล้ำออกนอกเสื้อผ้า!)
  // ---------------------------------------------------------------------------
  void _drawBorderlessPillBody(Canvas canvas, Offset center, double radius) {
    final pillBounds = Rect.fromCircle(center: center, radius: radius);
    final pillClipPath = Path()..addOval(pillBounds);

    // Clip the entire pill body + 3D rim inside pillClipPath so the shifted 3D rim
    // NEVER pokes out past the lower sides of the clothes!
    canvas.save();
    canvas.clipPath(pillClipPath);

    // Base 3D rim fill
    canvas.drawOval(pillBounds, Paint()..color = state.bodyRimColor);

    // Shifted front face of the 3D tablet inside the clipped pill circle
    final faceCenter = Offset(center.dx - state.rimOffsetX * 0.85, center.dy);
    final faceRect = Rect.fromCenter(
      center: faceCenter,
      width: radius * 1.96,
      height: radius * 2.0,
    );
    final bodyGradientPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.28, -0.35),
        radius: 0.92,
        colors: [
          Color.lerp(state.bodyColor, Colors.white, 0.18)!,
          state.bodyColor,
          state.bodyShadeColor,
        ],
        stops: const [0.0, 0.70, 1.0],
      ).createShader(faceRect);
    canvas.drawOval(faceRect, bodyGradientPaint);

    // Subtle 3D inner bevel highlight along the tablet edge
    canvas.drawOval(
      faceRect,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.32)
        ..strokeWidth = 1.8
        ..style = PaintingStyle.stroke,
    );

    // Signature Glossy White Highlight Arc + Dot on upper-left
    final glossPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.84)
      ..strokeWidth = 5.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius - 9.5),
      math.pi * 1.08,
      math.pi * 0.26,
      false,
      glossPaint,
    );
    canvas.drawCircle(
      Offset(
        center.dx + math.cos(math.pi * 1.01) * (radius - 9.5),
        center.dy + math.sin(math.pi * 1.01) * (radius - 9.5),
      ),
      3.2,
      Paint()..color = Colors.white.withValues(alpha: 0.84),
    );

    canvas.restore();
  }

  // ---------------------------------------------------------------------------
  // 4. Richly Detailed Outlined Clothing with Strictly Fitted Shadows
  //    (เงาทุกจุดถูก clip ให้พอดีอยู่ภายในเสื้อผ้า 100% ไม่ล้ำออกนอกเสื้อผ้า)
  // ---------------------------------------------------------------------------
  void _drawDetailedOutfit(Canvas canvas, Offset center, double radius) {
    final outlinePaint = Paint()
      ..color = state.clothesOutlineColor
      ..strokeWidth = 2.3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final seamPaint = Paint()
      ..color = state.clothesOutlineColor.withValues(alpha: 0.50)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final gapHalfWidth = 16.5 * state.coatOpenFactor;

    // For PRN blue character: draw an app-blue V-neck inner scrub shirt
    // inside the open coat gap (strictly clipped to the pill lower torso)
    if (state.prnFactor > 0.05 && gapHalfWidth > 0.5) {
      final prnAlpha = state.prnFactor.clamp(0.0, 1.0);
      final scrubPath = Path()
        ..moveTo(center.dx - gapHalfWidth - 4, center.dy + 24)
        ..quadraticBezierTo(
            center.dx, center.dy + 31, center.dx + gapHalfWidth + 4, center.dy + 24)
        ..lineTo(center.dx + gapHalfWidth + 4, center.dy + 59)
        ..quadraticBezierTo(
            center.dx, center.dy + 62, center.dx - gapHalfWidth - 4, center.dy + 59)
        ..close();
      canvas.save();
      canvas.clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: radius)));
      canvas.drawPath(
        scrubPath,
        Paint()..color = const Color(0xFF2463A6).withValues(alpha: prnAlpha),
      );
      canvas.drawPath(
        scrubPath,
        Paint()
          ..color = state.clothesOutlineColor.withValues(alpha: prnAlpha)
          ..strokeWidth = 1.8
          ..style = PaintingStyle.stroke,
      );
      canvas.restore();
    }

    // Left Torso Shirt / Coat Panel (contoured to fit the round pill body)
    final leftPanel = Path()
      ..moveTo(center.dx - 54, center.dy + 14)
      ..quadraticBezierTo(
          center.dx - 28, center.dy + 22, center.dx - gapHalfWidth, center.dy + 25)
      ..lineTo(
          center.dx - gapHalfWidth - 1.5 * state.coatOpenFactor, center.dy + 63)
      ..quadraticBezierTo(
          center.dx - 34, center.dy + 64, center.dx - 51, center.dy + 52)
      ..quadraticBezierTo(
          center.dx - 56, center.dy + 34, center.dx - 54, center.dy + 14)
      ..close();

    // Right Torso Shirt / Coat Panel
    final rightPanel = Path()
      ..moveTo(center.dx + 54, center.dy + 14)
      ..quadraticBezierTo(
          center.dx + 28, center.dy + 22, center.dx + gapHalfWidth, center.dy + 25)
      ..lineTo(
          center.dx + gapHalfWidth + 1.5 * state.coatOpenFactor, center.dy + 63)
      ..quadraticBezierTo(
          center.dx + 34, center.dy + 64, center.dx + 51, center.dy + 52)
      ..quadraticBezierTo(
          center.dx + 56, center.dy + 34, center.dx + 54, center.dy + 14)
      ..close();

    final combinedPanels =
        Path.combine(PathOperation.union, leftPanel, rightPanel);

    final notchDepth = 6.0 * state.coatOpenFactor;
    final leftCollar = Path()
      ..moveTo(center.dx - 50, center.dy + 13)
      ..lineTo(center.dx - gapHalfWidth, center.dy + 27)
      ..lineTo(center.dx - gapHalfWidth - 6, center.dy + 40)
      ..lineTo(center.dx - 32 + notchDepth, center.dy + 31)
      ..lineTo(center.dx - 36, center.dy + 34 - notchDepth)
      ..close();

    final rightCollar = Path()
      ..moveTo(center.dx + 50, center.dy + 13)
      ..lineTo(center.dx + gapHalfWidth, center.dy + 27)
      ..lineTo(center.dx + gapHalfWidth + 6, center.dy + 40)
      ..lineTo(center.dx + 32 - notchDepth, center.dy + 31)
      ..lineTo(center.dx + 36, center.dy + 34 - notchDepth)
      ..close();

    // Strictly clip ALL shirt fills, side shadows, collar shadows, pockets, and patterns
    // inside combinedPanels so NO shadow ever spills outside the clothing!
    canvas.save();
    canvas.clipPath(combinedPanels);

    final shirtRect = Rect.fromLTWH(center.dx - 58, center.dy + 12, 116, 56);
    final shirtFillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          state.clothesColor,
          Color.lerp(state.clothesColor, state.clothesShadeColor, 0.42)!,
        ],
      ).createShader(shirtRect);
    canvas.drawPath(combinedPanels, shirtFillPaint);

    // Fitted inner side shading
    final leftSideShade = Path()
      ..moveTo(center.dx - 54, center.dy + 14)
      ..quadraticBezierTo(
          center.dx - 44, center.dy + 36, center.dx - 38, center.dy + 63)
      ..lineTo(center.dx - 56, center.dy + 63)
      ..close();
    final rightSideShade = Path()
      ..moveTo(center.dx + 54, center.dy + 14)
      ..quadraticBezierTo(
          center.dx + 44, center.dy + 36, center.dx + 38, center.dy + 63)
      ..lineTo(center.dx + 56, center.dy + 63)
      ..close();
    canvas.drawPath(
      leftSideShade,
      Paint()..color = state.clothesShadeColor.withValues(alpha: 0.55),
    );
    canvas.drawPath(
      rightSideShade,
      Paint()..color = state.clothesShadeColor.withValues(alpha: 0.55),
    );

    // Evening pajama cute heart pattern (clipped inside shirt)
    if (state.patternOpacity > 0.02) {
      final pColor = const Color(0xFFB17CC6)
          .withValues(alpha: 0.80 * state.patternOpacity);
      for (final pt in const [
        Offset(-36, 34),
        Offset(-21, 43),
        Offset(-38, 49),
        Offset(-14, 53),
        Offset(18, 38),
        Offset(35, 33),
        Offset(23, 49),
        Offset(38, 48),
      ]) {
        _drawTinyHeart(canvas, center + pt, 3.2, pColor);
      }
    }

    // Pocket details (clipped inside shirt)
    if (state.coatOpenFactor < 0.5) {
      final pocketAlpha = (1.0 - state.coatOpenFactor * 2).clamp(0.0, 1.0);
      final effectiveAlpha = math.max(pocketAlpha, state.prnFactor);
      final pocketCenter = Offset(
        center.dx + (state.prnFactor > 0.5 ? 27 : 24),
        center.dy + (state.prnFactor > 0.5 ? 45 : 43),
      );
      final pocketRect = RRect.fromRectAndCorners(
        Rect.fromCenter(center: pocketCenter, width: 16, height: 13.5),
        bottomLeft: const Radius.circular(4),
        bottomRight: const Radius.circular(4),
      );
      canvas.drawRRect(
        pocketRect,
        Paint()
          ..color =
              state.clothesShadeColor.withValues(alpha: 0.65 * effectiveAlpha),
      );
      canvas.drawRRect(
        pocketRect,
        Paint()
          ..color = state.clothesOutlineColor
              .withValues(alpha: 0.75 * effectiveAlpha)
          ..strokeWidth = 1.6
          ..style = PaintingStyle.stroke,
      );

      // PRN Blue Medical Cross on Pocket + Stethoscope on Left Chest
      if (state.prnFactor > 0.05) {
        final prnA = state.prnFactor.clamp(0.0, 1.0);
        PillScenicBackdropPainter._drawMedicalCrossBadge(
          canvas,
          pocketCenter,
          3.8,
          const Color(0xFF2463A6).withValues(alpha: prnA),
        );

        // Stethoscope tubing & chestpiece on left chest panel
        final stethTube = Path()
          ..moveTo(center.dx - 28, center.dy + 22)
          ..quadraticBezierTo(
              center.dx - 34, center.dy + 35, center.dx - 26, center.dy + 45);
        canvas.drawPath(
          stethTube,
          Paint()
            ..color = const Color(0xFF184B82).withValues(alpha: prnA)
            ..strokeWidth = 2.5
            ..strokeCap = StrokeCap.round
            ..style = PaintingStyle.stroke,
        );
        final bellPos = Offset(center.dx - 26, center.dy + 46);
        canvas.drawCircle(
          bellPos,
          5.2,
          Paint()..color = const Color(0xFFEAF2FA).withValues(alpha: prnA),
        );
        canvas.drawCircle(
          bellPos,
          5.2,
          Paint()
            ..color = const Color(0xFF184B82).withValues(alpha: prnA)
            ..strokeWidth = 1.8
            ..style = PaintingStyle.stroke,
        );
        canvas.drawCircle(
          bellPos,
          2.2,
          Paint()..color = const Color(0xFF2463A6).withValues(alpha: prnA),
        );
      }
    } else {
      final coatAlpha = ((state.coatOpenFactor - 0.5) * 2).clamp(0.0, 1.0);
      for (final side in [-1.0, 1.0]) {
        canvas.drawLine(
          Offset(center.dx + side * 25, center.dy + 47),
          Offset(center.dx + side * 40, center.dy + 45),
          Paint()
            ..color =
                state.clothesOutlineColor.withValues(alpha: 0.8 * coatAlpha)
            ..strokeWidth = 2.0
            ..strokeCap = StrokeCap.round,
        );
      }
    }

    // Bottom hem stitch lines
    canvas.drawArc(
      Rect.fromLTRB(center.dx - 48, center.dy + 46,
          center.dx - gapHalfWidth - 2, center.dy + 60),
      0.15,
      math.pi * 0.65,
      false,
      seamPaint,
    );
    canvas.drawArc(
      Rect.fromLTRB(center.dx + gapHalfWidth + 2, center.dy + 46,
          center.dx + 48, center.dy + 60),
      0.2,
      math.pi * 0.65,
      false,
      seamPaint,
    );

    // Center button placket & 3D buttons (clipped inside combinedPanels)
    if (state.coatOpenFactor < 0.65 && state.prnFactor < 0.5) {
      final placketAlpha = (1.0 - state.coatOpenFactor * 1.5).clamp(0.0, 1.0);
      final placketPaint = Paint()
        ..color = state.clothesOutlineColor.withValues(alpha: placketAlpha)
        ..strokeWidth = 2.2;
      canvas.drawLine(
        Offset(center.dx, center.dy + 27),
        Offset(center.dx, center.dy + 64),
        placketPaint,
      );
      canvas.drawLine(
        Offset(center.dx - 4.5, center.dy + 28),
        Offset(center.dx - 4.5, center.dy + 64),
        Paint()
          ..color =
              state.clothesOutlineColor.withValues(alpha: 0.32 * placketAlpha)
          ..strokeWidth = 1.2,
      );

      for (final dy in [39.5, 52.0]) {
        final btnCenter = Offset(center.dx, center.dy + dy);
        canvas.drawCircle(
          btnCenter,
          3.5,
          Paint()
            ..color = state.clothesShadeColor.withValues(alpha: placketAlpha),
        );
        canvas.drawCircle(
          btnCenter,
          3.5,
          Paint()
            ..color = state.clothesOutlineColor.withValues(alpha: placketAlpha)
            ..strokeWidth = 1.6
            ..style = PaintingStyle.stroke,
        );
        canvas.drawCircle(
          btnCenter + const Offset(-1.0, 0),
          0.7,
          Paint()
            ..color = state.clothesOutlineColor.withValues(alpha: placketAlpha),
        );
        canvas.drawCircle(
          btnCenter + const Offset(1.0, 0),
          0.7,
          Paint()
            ..color = state.clothesOutlineColor.withValues(alpha: placketAlpha),
        );
      }
    }

    // Collar underside shadow strictly clipped inside combinedPanels!
    canvas.save();
    canvas.translate(0, 2.2);
    canvas.drawPath(
      leftCollar,
      Paint()..color = state.clothesOutlineColor.withValues(alpha: 0.18),
    );
    canvas.drawPath(
      rightCollar,
      Paint()..color = state.clothesOutlineColor.withValues(alpha: 0.18),
    );
    canvas.restore();

    canvas.restore(); // End clipPath(combinedPanels)

    // Draw crisp outlines around shirt/coat panels
    canvas.drawPath(leftPanel, outlinePaint);
    canvas.drawPath(rightPanel, outlinePaint);

    // Draw folded collars on top with crisp outlines
    final collarFill = Paint()
      ..color = Color.lerp(state.clothesColor, Colors.white, 0.35)!;
    canvas.drawPath(leftCollar, collarFill);
    canvas.drawPath(rightCollar, collarFill);
    canvas.drawPath(leftCollar, outlinePaint);
    canvas.drawPath(rightCollar, outlinePaint);
  }

  void _drawTinyHeart(
      Canvas canvas, Offset center, double size, Color color) {
    final path = Path()
      ..moveTo(center.dx, center.dy + size * 0.6)
      ..cubicTo(
        center.dx - size * 1.1,
        center.dy,
        center.dx - size * 0.6,
        center.dy - size * 0.8,
        center.dx,
        center.dy - size * 0.25,
      )
      ..cubicTo(
        center.dx + size * 0.6,
        center.dy - size * 0.8,
        center.dx + size * 1.1,
        center.dy,
        center.dx,
        center.dy + size * 0.6,
      )
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  // ---------------------------------------------------------------------------
  // 5. Front Arm & Teddy Bear (Bedtime Morph)
  // ---------------------------------------------------------------------------
  void _drawFrontArmsAndTeddy(Canvas canvas, Offset center) {
    if (state.teddyBearFactor <= 0.02) return;

    final scale = state.teddyBearFactor.clamp(0.0, 1.0);
    final rockAngle = limbPhase * 0.08;
    final bearCenter = Offset(center.dx + 31, center.dy + 33);

    canvas.save();
    canvas.translate(bearCenter.dx, bearCenter.dy);
    canvas.rotate(rockAngle);
    canvas.scale(scale, scale);

    const furColor = Color(0xFFC87D4B);
    const innerEarColor = Color(0xFFE6A473);
    const snoutColor = Color(0xFFF3C38E);
    const bearOutlineColor = Color(0xFF593118);

    final bearOutline = Paint()
      ..color = bearOutlineColor
      ..strokeWidth = 1.9
      ..style = PaintingStyle.stroke;

    for (final earOffset in const [Offset(-11, -18), Offset(11, -17)]) {
      canvas.drawCircle(earOffset, 6.5, Paint()..color = furColor);
      canvas.drawCircle(earOffset, 6.5, bearOutline);
      canvas.drawCircle(earOffset, 3.2, Paint()..color = innerEarColor);
    }

    final bodyRect =
        Rect.fromCenter(center: const Offset(-1, 14), width: 24, height: 26);
    canvas.drawOval(bodyRect, Paint()..color = furColor);
    canvas.drawOval(bodyRect, bearOutline);

    const headCenter = Offset(0, -6);
    canvas.drawCircle(headCenter, 14, Paint()..color = furColor);
    canvas.drawCircle(headCenter, 14, bearOutline);

    final snoutRect =
        Rect.fromCenter(center: const Offset(0, -3), width: 12, height: 9);
    canvas.drawOval(snoutRect, Paint()..color = snoutColor);
    canvas.drawCircle(
        const Offset(0, -5), 2.0, Paint()..color = bearOutlineColor);
    canvas.drawCircle(
        const Offset(-5, -8), 1.8, Paint()..color = bearOutlineColor);
    canvas.drawCircle(
        const Offset(5, -8), 1.8, Paint()..color = bearOutlineColor);

    canvas.restore();

    if (state.teddyBearFactor >= 0.85) {
      final armSwing = limbPhase * 2.5;
      final armPath = Path()
        ..moveTo(center.dx + 48, center.dy + 21)
        ..quadraticBezierTo(
          center.dx + 57,
          center.dy + 41 + armSwing,
          center.dx + 28,
          center.dy + 42 + armSwing,
        );
      canvas.drawPath(
        armPath,
        Paint()
          ..color = state.clothesOutlineColor
          ..strokeWidth = 17.5
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke,
      );
      canvas.drawPath(
        armPath,
        Paint()
          ..color = state.clothesColor
          ..strokeWidth = 13.0
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke,
      );
      final handCenter = Offset(center.dx + 23, center.dy + 41 + armSwing);
      canvas.drawCircle(handCenter, 7.0, Paint()..color = state.bodyColor);
    }
  }

  // ---------------------------------------------------------------------------
  // 6. Morphing Headgear (Nurse Cap <-> PRN Blue Medical Cap <-> Sleeping Nightcap)
  // ---------------------------------------------------------------------------
  void _drawMorphingHeadgear(Canvas canvas, Offset center, double radius) {
    final nurseAlpha = (1.0 - state.nightCapFactor).clamp(0.0, 1.0);
    final nightAlpha = state.nightCapFactor.clamp(0.0, 1.0);

    if (nurseAlpha > 0.01) {
      canvas.save();
      final capCenter = Offset(center.dx, center.dy - radius - 4);
      canvas.translate(capCenter.dx, capCenter.dy);
      canvas.scale(nurseAlpha, nurseAlpha);

      final capPath = Path()
        ..moveTo(-22, 10)
        ..lineTo(-27, -6)
        ..quadraticBezierTo(0, -15, 27, -6)
        ..lineTo(22, 10)
        ..quadraticBezierTo(0, 6, -22, 10)
        ..close();

      canvas.save();
      canvas.clipPath(capPath);
      canvas.drawPath(
        capPath,
        Paint()
          ..color = Color.lerp(
            Colors.white,
            const Color(0xFFF4F9FF),
            state.prnFactor.clamp(0.0, 1.0),
          )!,
      );
      final rimPath = Path()
        ..moveTo(-24, 5)
        ..quadraticBezierTo(0, 1, 24, 5)
        ..lineTo(24, 12)
        ..lineTo(-24, 12)
        ..close();
      canvas.drawPath(
        rimPath,
        Paint()
          ..color = Color.lerp(
            const Color(0xFFD6ECF8),
            const Color(0xFFC5E0FA),
            state.prnFactor.clamp(0.0, 1.0),
          )!,
      );
      canvas.restore();

      canvas.drawPath(
        capPath,
        Paint()
          ..color = Color.lerp(
            const Color(0xFF5D8AA8),
            const Color(0xFF184B82),
            state.prnFactor.clamp(0.0, 1.0),
          )!
          ..strokeWidth = 2.1
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round,
      );

      if (state.prnFactor > 0.5) {
        PillScenicBackdropPainter._drawMedicalCrossBadge(
          canvas,
          const Offset(0, -2),
          5.2,
          const Color(0xFF2463A6),
        );
      } else {
        _drawHeart(canvas, const Offset(0, -2), 6.5, const Color(0xFFE64839));
      }
      canvas.restore();
    }

    if (nightAlpha > 0.01) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.scale(nightAlpha, nightAlpha);

      final outlinePaint = Paint()
        ..color = state.clothesOutlineColor
        ..strokeWidth = 2.1
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round;

      final tipSway = limbPhase * 3.0;
      final capPath = Path()
        ..moveTo(-16, -54)
        ..quadraticBezierTo(26, -78, 58, -26 + tipSway)
        ..quadraticBezierTo(42, -24 + tipSway, 34, -36)
        ..close();

      canvas.save();
      canvas.clipPath(capPath);
      canvas.drawPath(capPath, Paint()..color = const Color(0xFF849FD4));
      canvas.drawPath(
        Path()
          ..moveTo(-16, -54)
          ..quadraticBezierTo(18, -50, 58, -26 + tipSway)
          ..lineTo(34, -36)
          ..close(),
        Paint()..color = const Color(0xFF6B86BF),
      );
      canvas.restore();
      canvas.drawPath(capPath, outlinePaint);

      final cuffPath = Path()
        ..moveTo(-20, -52)
        ..quadraticBezierTo(12, -46, 40, -28)
        ..quadraticBezierTo(46, -34, 40, -40)
        ..quadraticBezierTo(14, -58, -14, -60)
        ..close();
      canvas.drawPath(cuffPath, Paint()..color = const Color(0xFFC9DDFB));
      canvas.drawPath(cuffPath, outlinePaint);

      final pomCenter = Offset(56, -20 + tipSway);
      canvas.drawCircle(
          pomCenter, 9.5, Paint()..color = const Color(0xFFCFE2FC));
      canvas.drawCircle(pomCenter, 9.5, outlinePaint);

      canvas.restore();
    }
  }

  void _drawHeart(Canvas canvas, Offset center, double size, Color color) {
    final path = Path()
      ..moveTo(center.dx, center.dy + size * 0.65)
      ..cubicTo(
        center.dx - size * 1.2,
        center.dy + size * 0.1,
        center.dx - size * 0.7,
        center.dy - size * 0.9,
        center.dx,
        center.dy - size * 0.3,
      )
      ..cubicTo(
        center.dx + size * 0.7,
        center.dy - size * 0.9,
        center.dx + size * 1.2,
        center.dy + size * 0.1,
        center.dx,
        center.dy + size * 0.65,
      )
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  // ---------------------------------------------------------------------------
  // 7. Morphing Facial Features (with adorable Evening dreamy eyes!)
  // ---------------------------------------------------------------------------
  void _drawFacialFeatures(Canvas canvas, Offset center) {
    final faceColor = state.darkFaceColor;

    // Rosy oval cheeks
    final cheekPaint = Paint()..color = state.cheekColor.withValues(alpha: 0.82);
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(center.dx - 31, center.dy - 1), width: 17, height: 9.5),
      cheekPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(center.dx + 31, center.dy - 1), width: 17, height: 9.5),
      cheekPaint,
    );

    // Eyebrows
    final browPaint = Paint()
      ..color = faceColor
      ..strokeWidth = 2.8
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final browLift = limbPhase * 1.1;
    final leftBrow = Path()
      ..moveTo(center.dx - 26, center.dy - 24 - browLift)
      ..quadraticBezierTo(center.dx - 20, center.dy - 28 - browLift,
          center.dx - 14, center.dy - 25 - browLift);
    final rightBrow = Path()
      ..moveTo(center.dx + 14, center.dy - 25 + browLift)
      ..quadraticBezierTo(center.dx + 20, center.dy - 28 + browLift,
          center.dx + 26, center.dy - 24 + browLift);
    canvas.drawPath(leftBrow, browPaint);
    canvas.drawPath(rightBrow, browPaint);

    // Eyes
    if (state.eyeOpenness > 0.25) {
      final eyeHeight = 16.0 * state.eyeOpenness.clamp(0.45, 1.0);
      for (final dx in [-20.0, 20.0]) {
        final eyePos = Offset(center.dx + dx, center.dy - 11.5);
        final eyeRect =
            Rect.fromCenter(center: eyePos, width: 14.8, height: eyeHeight);
        final eyeClip = Path()..addOval(eyeRect);

        // 1) Rich dark glossy cartoon eye base with sparkly white shine dots
        canvas.save();
        canvas.clipPath(eyeClip);
        canvas.drawOval(eyeRect, Paint()..color = faceColor);

        // Warm subtle lower iris glow
        canvas.drawOval(
          Rect.fromCenter(
              center: Offset(eyePos.dx, eyePos.dy + 5.5), width: 11, height: 5),
          Paint()..color = Colors.white.withValues(alpha: 0.18),
        );

        // Dual sparkly white highlights (shifted slightly lower when sleepy so they stay visible and cute!)
        final shineShiftY = 2.6 * state.eyelidDroop;
        canvas.drawCircle(
          Offset(eyePos.dx + (dx < 0 ? 2.4 : -2.4), eyePos.dy - 2.8 + shineShiftY),
          3.1,
          Paint()..color = Colors.white,
        );
        canvas.drawCircle(
          Offset(eyePos.dx + (dx < 0 ? -2.6 : 2.6), eyePos.dy + 3.0),
          1.6,
          Paint()..color = Colors.white,
        );

        // 2) Soft curved sleepy upper eyelid (for Evening / morphing)
        if (state.eyelidDroop > 0.05) {
          final droopY =
              ui.lerpDouble(eyePos.dy - 9.0, eyePos.dy - 0.5, state.eyelidDroop)!;
          final lidPath = Path()
            ..moveTo(eyePos.dx - 10, eyePos.dy - 10)
            ..lineTo(eyePos.dx + 10, eyePos.dy - 10)
            ..lineTo(eyePos.dx + 10, droopY)
            ..quadraticBezierTo(
                eyePos.dx, droopY + 2.2, eyePos.dx - 10, droopY)
            ..close();
          canvas.drawPath(
            lidPath,
            Paint()
              ..color = Color.lerp(state.bodyShadeColor, state.bodyRimColor, 0.55)!,
          );
        }
        canvas.restore();

        // 3) Soft curved upper eyelash line when sleepy (Evening)
        if (state.eyelidDroop > 0.08) {
          final droopY =
              ui.lerpDouble(eyePos.dy - 8.5, eyePos.dy - 0.5, state.eyelidDroop)!;
          final lashCurve = Path()
            ..moveTo(eyePos.dx - 7.8, droopY - 0.3)
            ..quadraticBezierTo(
                eyePos.dx, droopY + 2.2, eyePos.dx + 7.8, droopY - 0.3);
          canvas.drawPath(
            lashCurve,
            Paint()
              ..color = faceColor
              ..strokeWidth = 2.4
              ..strokeCap = StrokeCap.round
              ..style = PaintingStyle.stroke,
          );
        }
      }
    } else {
      // Peaceful closed sleeping eyes (Bedtime)
      final sleepEyePaint = Paint()
        ..color = faceColor
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;

      final leftSleep = Path()
        ..moveTo(center.dx - 27, center.dy - 12)
        ..quadraticBezierTo(
            center.dx - 20, center.dy - 5, center.dx - 13, center.dy - 12);
      final rightSleep = Path()
        ..moveTo(center.dx + 13, center.dy - 12)
        ..quadraticBezierTo(
            center.dx + 20, center.dy - 5, center.dx + 27, center.dy - 12);
      canvas.drawPath(leftSleep, sleepEyePaint);
      canvas.drawPath(rightSleep, sleepEyePaint);
    }

    // Morphing Mouth
    final mouthCenter = Offset(center.dx, center.dy - 2);
    if (state.sleepMouthFactor > 0.5) {
      final sleepMouth = Rect.fromCenter(
        center: Offset(center.dx, center.dy + 1),
        width: 9.5,
        height: 6.5,
      );
      canvas.drawOval(sleepMouth, Paint()..color = const Color(0xFF8C3636));
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(center.dx, center.dy + 2), width: 6, height: 3.5),
        Paint()..color = const Color(0xFFD96B6B),
      );
      canvas.drawOval(
        sleepMouth,
        Paint()
          ..color = faceColor
          ..strokeWidth = 1.6
          ..style = PaintingStyle.stroke,
      );
    } else if (state.mouthOpenness > 0.25) {
      final openDepth = 12.0 * state.mouthOpenness;
      final halfW = 10.0 + 3.0 * state.teethFactor;
      final mouthPath = Path()
        ..moveTo(mouthCenter.dx - halfW, mouthCenter.dy - 2)
        ..quadraticBezierTo(mouthCenter.dx, mouthCenter.dy - 1,
            mouthCenter.dx + halfW, mouthCenter.dy - 2)
        ..quadraticBezierTo(
            mouthCenter.dx + halfW - 1.5,
            mouthCenter.dy + openDepth,
            mouthCenter.dx,
            mouthCenter.dy + openDepth)
        ..quadraticBezierTo(
            mouthCenter.dx - halfW + 1.5,
            mouthCenter.dy + openDepth,
            mouthCenter.dx - halfW,
            mouthCenter.dy - 2)
        ..close();

      canvas.drawPath(mouthPath, Paint()..color = const Color(0xFF7D241E));
      canvas.save();
      canvas.clipPath(mouthPath);
      if (state.teethFactor > 0.1) {
        canvas.drawRect(
          Rect.fromLTWH(mouthCenter.dx - 14, mouthCenter.dy - 4, 28,
              5.5 * state.teethFactor),
          Paint()..color = Colors.white,
        );
      }
      canvas.drawOval(
        Rect.fromCenter(
            center: Offset(mouthCenter.dx, mouthCenter.dy + openDepth - 2),
            width: 16,
            height: 10),
        Paint()..color = const Color(0xFFF46854),
      );
      canvas.restore();
      canvas.drawPath(
        mouthPath,
        Paint()
          ..color = faceColor
          ..strokeWidth = 2.0
          ..style = PaintingStyle.stroke,
      );
    } else {
      final smilePath = Path()
        ..moveTo(center.dx - 9.5, center.dy - 1)
        ..quadraticBezierTo(
            center.dx, center.dy + 6.5, center.dx + 9.5, center.dy - 1);
      canvas.drawPath(
        smilePath,
        Paint()
          ..color = faceColor
          ..strokeWidth = 2.6
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant PillVectorPainter oldDelegate) {
    return oldDelegate.state != state ||
        oldDelegate.isTaken != isTaken ||
        oldDelegate.animValue != animValue ||
        oldDelegate.limbPhase != limbPhase ||
        oldDelegate.bounceOffset != bounceOffset ||
        oldDelegate.squash != squash ||
        oldDelegate.tilt != tilt ||
        oldDelegate.showBackground != showBackground;
  }
}
