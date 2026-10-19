import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/medis_theme.dart';

class SlideToConfirm extends StatefulWidget {
  const SlideToConfirm(
      {required this.label,
      required this.onConfirmed,
      this.enabled = true,
      this.color = MeDisColors.primary,
      this.sliderKey = const Key('slide-to-confirm'),
      super.key});

  final String label;
  final VoidCallback onConfirmed;
  final bool enabled;
  final Color color;
  final Key sliderKey;

  @override
  State<SlideToConfirm> createState() => _SlideToConfirmState();
}

class _SlideToConfirmState extends State<SlideToConfirm> {
  double progress = 0;
  bool pointerInteraction = false;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 72,
        child: Stack(alignment: Alignment.center, children: [
          Positioned.fill(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 56,
                  trackShape: const RoundedRectSliderTrackShape(),
                  activeTrackColor: widget.color,
                  inactiveTrackColor: widget.color,
                  disabledActiveTrackColor: MeDisColors.border,
                  disabledInactiveTrackColor: MeDisColors.border,
                  thumbColor: Colors.white,
                  disabledThumbColor: MeDisColors.border,
                  thumbShape: const _ConfirmationThumb(),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 28),
                  overlayColor: widget.color.withValues(alpha: .18),
                ),
                child: Listener(
                    onPointerDown: (_) => pointerInteraction = true,
                    onPointerUp: (_) =>
                        scheduleMicrotask(() => pointerInteraction = false),
                    onPointerCancel: (_) {
                      pointerInteraction = false;
                      setState(() => progress = 0);
                    },
                    child: Slider(
                      key: widget.sliderKey,
                      value: progress,
                      allowedInteraction: SliderInteraction.slideThumb,
                      semanticFormatterCallback: (value) =>
                          '${widget.label} ${(value * 100).round()} เปอร์เซ็นต์',
                      onChanged: widget.enabled
                          ? (value) => setState(() => progress = value)
                          : null,
                      onChangeEnd: widget.enabled
                          ? (value) {
                              if (value >= .98) {
                                setState(() => progress = 0);
                                widget.onConfirmed();
                              } else if (pointerInteraction) {
                                setState(() => progress = 0);
                              }
                            }
                          : null,
                    )),
              ),
            ),
          ),
          IgnorePointer(
            child: Padding(
              padding: const EdgeInsets.only(left: 64, right: 26),
              child: SizedBox(
                width: double.infinity,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Opacity(
                      opacity: (1 - progress * 1.6).clamp(0, 1),
                      child: Text(widget.label,
                          key: const Key('slide-track-text'),
                          maxLines: 1,
                          style: TextStyle(
                              color: widget.enabled
                                  ? Colors.white
                                  : MeDisColors.muted,
                              fontWeight: FontWeight.w700,
                              fontSize: 15))),
                ),
              ),
            ),
          ),
        ]),
      );
}

class _ConfirmationThumb extends SliderComponentShape {
  const _ConfirmationThumb();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(44, 44);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    canvas.drawCircle(center, 22, Paint()..color = Colors.white);
    final arrow = Path()
      ..moveTo(center.dx - 3, center.dy - 7)
      ..lineTo(center.dx + 4, center.dy)
      ..lineTo(center.dx - 3, center.dy + 7);
    canvas.drawPath(
        arrow,
        Paint()
          ..color = Color.lerp(MeDisColors.subtle, sliderTheme.activeTrackColor,
              enableAnimation.value)!
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round);
  }
}
