import 'package:flutter/material.dart';

import '../theme/medis_theme.dart';

/// Shared structure for scheduled and as-needed medication on the Today page.
class MeDisMedicationCard extends StatelessWidget {
  const MeDisMedicationCard(
      {required this.title,
      required this.subtitle,
      required this.icon,
      required this.expanded,
      required this.children,
      this.onToggle,
      this.highlighted = false,
      this.trailing,
      this.status,
      super.key});

  final String title;
  final String subtitle;
  final IconData icon;
  final bool expanded;
  final bool highlighted;
  final VoidCallback? onToggle;
  final Widget? trailing;
  final Widget? status;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 16),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MeDisRadius.card),
            side: BorderSide(
                color: highlighted ? MeDisColors.primary : MeDisColors.border,
                width: highlighted ? 1.5 : 1)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            InkWell(
              onTap: onToggle,
              borderRadius: BorderRadius.circular(MeDisRadius.input),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(children: [
                  Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                          color: MeDisColors.primarySoft,
                          borderRadius: BorderRadius.circular(14)),
                      child: Icon(icon, color: MeDisColors.primary, size: 28)),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(title,
                            style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                height: 1.4)),
                        const SizedBox(height: 4),
                        Text(subtitle,
                            style: const TextStyle(
                                fontSize: 16,
                                color: MeDisColors.muted,
                                height: 1.5)),
                      ])),
                  const SizedBox(width: 8),
                  trailing ??
                      Icon(expanded ? Icons.expand_less : Icons.expand_more,
                          size: 28, color: MeDisColors.muted),
                ]),
              ),
            ),
            if (status != null) ...[const SizedBox(height: 8), status!],
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 200),
              crossFadeState: expanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: const SizedBox(width: double.infinity),
              secondChild: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [const Divider(height: 28), ...children]),
            ),
          ]),
        ),
      );
}
