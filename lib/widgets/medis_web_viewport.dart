import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/medis_theme.dart';

/// iPhone 17 Pro Max's 1320 × 2868 display expressed at 3× scale.
class MeDisWebViewport extends StatelessWidget {
  const MeDisWebViewport({required this.child, super.key});

  static const screenSize = Size(440, 956);
  final Widget child;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: MeDisColors.border,
        child: LayoutBuilder(builder: (context, constraints) {
          if (constraints.maxWidth <= 0 || constraints.maxHeight <= 0) {
            return const SizedBox.shrink();
          }
          final scale = math.min(
              1.0,
              math.min(constraints.maxWidth / screenSize.width,
                  constraints.maxHeight / screenSize.height));
          final media = MediaQuery.of(context);
          return Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: SizedBox.fromSize(
                size: screenSize,
                child: MediaQuery(
                  data: media.copyWith(
                    size: screenSize,
                    padding: media.padding / scale,
                    viewPadding: media.viewPadding / scale,
                    viewInsets: media.viewInsets / scale,
                    alwaysUse24HourFormat: true,
                  ),
                  child: ClipRect(
                    child:
                        ColoredBox(color: MeDisColors.background, child: child),
                  ),
                ),
              ),
            ),
          );
        }),
      );
}
