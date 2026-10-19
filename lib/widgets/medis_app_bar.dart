import 'package:flutter/material.dart';

class MeDisAppBar extends StatelessWidget implements PreferredSizeWidget {
  const MeDisAppBar(this.title, {this.actions, super.key});
  final String title;
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) => AppBar(
        actions: actions,
        title: Text(title,
            maxLines: 2, style: Theme.of(context).textTheme.titleLarge),
      );
}
