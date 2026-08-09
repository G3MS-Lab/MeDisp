import 'package:flutter/material.dart';

import 'application/app_controller.dart';
import 'application/app_scope.dart';
import 'data/in_memory_repositories.dart';
import 'screens/daily_screen.dart';
import 'screens/hub_screen.dart';
import 'screens/profile_screen.dart';

void main() {
  final controller = AppController(InMemoryDispenserRepository(), InMemoryMedicationRepository());
  runApp(AppScope(controller: controller, child: MeDisApp(controller: controller)));
}

class MeDisApp extends StatefulWidget {
  const MeDisApp({required this.controller, super.key});
  final AppController controller;

  @override
  State<MeDisApp> createState() => _MeDisAppState();
}

class _MeDisAppState extends State<MeDisApp> {
  @override
  void initState() {
    super.initState();
    widget.controller.initialize();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'MeDis',
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: Colors.white,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6AA6FF)),
          inputDecorationTheme: InputDecorationTheme(border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)), filled: true, fillColor: const Color(0xFFF8FAFD)),
          cardTheme: CardThemeData(color: Colors.white, elevation: 5, shadowColor: const Color(0x33001226), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
        ),
        home: const MeDisShell(),
      );
}

class MeDisShell extends StatefulWidget {
  const MeDisShell({super.key});
  @override
  State<MeDisShell> createState() => _MeDisShellState();
}

class _MeDisShellState extends State<MeDisShell> {
  int index = 1;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(child: IndexedStack(index: index, children: const [HubScreen(), DailyScreen(), ProfileScreen()])),
        bottomNavigationBar: NavigationBar(
          height: 76,
          selectedIndex: index,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
          indicatorColor: const Color(0xFF6AA6FF),
          onDestinationSelected: (value) => setState(() => index = value),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.grid_view_rounded), label: 'Menu'),
            NavigationDestination(icon: Icon(Icons.monitor_heart_outlined, color: Colors.white), label: 'Today'),
            NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profile'),
          ],
        ),
      );
