import 'package:flutter/material.dart';

import '../theme/medis_theme.dart';
import 'slide_to_confirm.dart';

class MeDisSelectionTile extends StatelessWidget {
  const MeDisSelectionTile(
      {required this.title,
      required this.icon,
      required this.selected,
      required this.onTap,
      super.key});
  final String title;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: selected ? MeDisColors.primarySoft : MeDisColors.surface,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(MeDisRadius.input),
              side: BorderSide(
                  color: selected ? MeDisColors.primary : MeDisColors.border,
                  width: selected ? 1.5 : 1)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Icon(icon, color: MeDisColors.primary, size: 28),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(title,
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            height: 1.5))),
                const SizedBox(width: 8),
                Icon(
                    selected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: selected ? MeDisColors.primary : MeDisColors.subtle,
                    size: 24),
              ]),
            ),
          ),
        ),
      );
}

class MeDisPageHeader extends StatelessWidget {
  const MeDisPageHeader(
      {required this.title, required this.subtitle, this.trailing, super.key});
  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: MeDisSpace.xl),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title, style: Theme.of(context).textTheme.headlineMedium),
                const SizedBox(height: MeDisSpace.xs),
                Text(subtitle,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: MeDisColors.muted)),
              ])),
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
        ]),
      );
}

class MeDisEmptyState extends StatelessWidget {
  const MeDisEmptyState(
      {required this.icon,
      required this.title,
      required this.message,
      this.action,
      super.key});
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              padding: const EdgeInsets.all(18),
              decoration: const BoxDecoration(
                  color: MeDisColors.primarySoft, shape: BoxShape.circle),
              child: Icon(icon, size: 32, color: MeDisColors.primary)),
          const SizedBox(height: 16),
          Text(title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(message,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: MeDisColors.muted)),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ]),
      );
}

class MeDisSection extends StatelessWidget {
  const MeDisSection(
      {required this.title,
      required this.children,
      this.icon,
      this.bottomSpacing = MeDisSpace.lg,
      super.key});
  final String title;
  final IconData? icon;
  final List<Widget> children;
  final double bottomSpacing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: bottomSpacing),
        child: Card(
            child: Padding(
          padding: const EdgeInsets.all(MeDisSpace.page),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (icon != null) ...[
                Icon(icon, color: MeDisColors.primary, size: 22),
                const SizedBox(width: 10)
              ],
              Expanded(
                  child: Text(title,
                      style: Theme.of(context).textTheme.titleMedium)),
            ]),
            const SizedBox(height: 16),
            ...children,
          ]),
        )),
      );
}

class MeDisNotice extends StatelessWidget {
  const MeDisNotice(
      {required this.message,
      this.icon = Icons.info_outline,
      this.color = MeDisColors.primary,
      super.key});
  final String message;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: color.withValues(alpha: .07),
            borderRadius: BorderRadius.circular(MeDisRadius.input)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 12),
          Expanded(
              child:
                  Text(message, style: TextStyle(color: color, height: 1.5))),
        ]),
      );
}

Future<bool> confirmMeDisAction(BuildContext context,
        {required String title,
        required String message,
        required String actionLabel,
        bool destructive = false}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(title),
        content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message),
                const SizedBox(height: 16),
                SlideToConfirm(
                    sliderKey: const Key('confirm-action-slider'),
                    color:
                        destructive ? MeDisColors.error : MeDisColors.primary,
                    label: 'สไลด์เพื่อ$actionLabel',
                    onConfirmed: () => Navigator.pop(context, true)),
              ],
            )),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('ยกเลิก')),
        ],
      ),
    ) ??
    false;
