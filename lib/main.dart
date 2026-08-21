import 'package:flutter/material.dart';

import 'application/app_controller.dart';
import 'application/app_scope.dart';
import 'data/auth_repositories.dart';
import 'data/persistent_dispenser_repository.dart';
import 'data/persistent_medication_repository.dart';
import 'domain/repositories.dart';
import 'screens/daily_screen.dart';
import 'screens/hub_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/auth_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final authRepository = OfflineAuthRepository(SecureAuthStorage());
  await authRepository.initialize();
  final MedicationRepository medicationRepository =
      PersistentMedicationRepository(authRepository);
  final DispenserRepository dispenserRepository =
      PersistentDispenserRepository(authRepository);
  final controller =
      AppController(authRepository, dispenserRepository, medicationRepository);
  await controller.initialize();
  runApp(AppScope(
      controller: controller, child: MeDisApp(controller: controller)));
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
    if (!widget.controller.initialized) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.controller.initialize();
      });
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'MeDis',
        theme: ThemeData(
          useMaterial3: true,
          scaffoldBackgroundColor: Colors.white,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6AA6FF)),
          inputDecorationTheme: InputDecorationTheme(
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              filled: true,
              fillColor: const Color(0xFFF8FAFD)),
          cardTheme: CardThemeData(
              color: Colors.white,
              elevation: 5,
              shadowColor: const Color(0x33001226),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16))),
        ),
        home: const AuthGate(),
      );
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    if (!controller.initialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return controller.user == null ? const AuthScreen() : const MeDisShell();
  }
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
        body: SafeArea(
            child: IndexedStack(
                index: index,
                children: const [HubScreen(), DailyScreen(), ProfileScreen()])),
        bottomNavigationBar: NavigationBar(
          height: 76,
          selectedIndex: index,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
          indicatorColor: const Color(0xFF6AA6FF),
          onDestinationSelected: (value) => setState(() => index = value),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.grid_view_rounded), label: 'Menu'),
            NavigationDestination(
                icon: Icon(Icons.monitor_heart_outlined, color: Colors.white),
                label: 'Today'),
            NavigationDestination(
                icon: Icon(Icons.person_outline), label: 'Profile'),
          ],
        ),
      );
}
