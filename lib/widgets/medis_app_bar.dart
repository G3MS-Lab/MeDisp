import 'package:flutter/material.dart';

class MeDisAppBar extends StatelessWidget implements PreferredSizeWidget {
  const MeDisAppBar(this.title, {super.key});
  final String title;

  @override
  Size get preferredSize => const Size.fromHeight(76);

  @override
  Widget build(BuildContext context) => AppBar(
        toolbarHeight: 76,
        backgroundColor: const Color(0xFFAACBFA),
        foregroundColor: Colors.white,
        centerTitle: true,
        title: Text(title, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w600)),
      );
}
