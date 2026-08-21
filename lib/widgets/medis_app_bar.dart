import 'package:flutter/material.dart';

class MeDisAppBar extends StatelessWidget implements PreferredSizeWidget {
  const MeDisAppBar(this.title, {this.actions, super.key});
  final String title;
  final List<Widget>? actions;

  @override
  Size get preferredSize => const Size.fromHeight(76);

  @override
  Widget build(BuildContext context) => AppBar(
        toolbarHeight: 76,
        backgroundColor: const Color(0xFFAACBFA),
        foregroundColor: Colors.white,
        centerTitle: true,
        actions: actions,
        title: Text(title,
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w600)),
      );
}
