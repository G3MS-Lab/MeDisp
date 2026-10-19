import 'package:flutter/material.dart';

class SlideToConfirm extends StatefulWidget {
  const SlideToConfirm(
      {required this.label,
      required this.onConfirmed,
      this.enabled = true,
      this.sliderKey = const Key('slide-to-confirm'),
      super.key});

  final String label;
  final VoidCallback onConfirmed;
  final bool enabled;
  final Key sliderKey;

  @override
  State<SlideToConfirm> createState() => _SlideToConfirmState();
}

class _SlideToConfirmState extends State<SlideToConfirm> {
  double progress = 0;

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
                  activeTrackColor: const Color(0xFF2563EB),
                  inactiveTrackColor: const Color(0xFF3B75BA),
                  disabledActiveTrackColor: const Color(0xFFB8C2D0),
                  disabledInactiveTrackColor: const Color(0xFFB8C2D0),
                  thumbColor: Colors.white,
                  disabledThumbColor: const Color(0xFFE4E8EF),
                  thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 22,
                      elevation: 2,
                      pressedElevation: 4),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 28),
                  overlayColor: Colors.transparent,
                ),
                child: Slider(
                  key: widget.sliderKey,
                  value: progress,
                  allowedInteraction: SliderInteraction.slideThumb,
                  semanticFormatterCallback: (_) => widget.label,
                  onChanged: widget.enabled
                      ? (value) => setState(() => progress = value)
                      : null,
                  onChangeEnd: widget.enabled
                      ? (value) {
                          if (mounted) setState(() => progress = 0);
                          if (value >= .98) widget.onConfirmed();
                        }
                      : null,
                ),
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
                  child: Text(widget.label,
                      key: const Key('slide-track-text'),
                      maxLines: 1,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 15)),
                ),
              ),
            ),
          ),
        ]),
      );
}
