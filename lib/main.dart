import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'application/app_controller.dart';
import 'application/app_scope.dart';
import 'data/auth_repositories.dart';
import 'data/local_image_store.dart';
import 'data/persistent_dispenser_repository.dart';
import 'data/persistent_medication_repository.dart';
import 'domain/repositories.dart';
import 'screens/daily_screen.dart';
import 'screens/hub_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/auth_screen.dart';
import 'theme/medis_theme.dart';
import 'widgets/medis_web_viewport.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await const LocalImageStore().migrateLegacyImages();
  final authRepository = OfflineAuthRepository(SecureAuthStorage());
  await authRepository.initialize();
  final MedicationRepository medicationRepository =
      PersistentMedicationRepository(authRepository);
  final DispenserRepository dispenserRepository =
      PersistentDispenserRepository(authRepository);
  final controller =
      AppController(authRepository, dispenserRepository, medicationRepository);
  await controller.initialize();
  runApp(
    AppScope(
      controller: controller,
      child: MeDisApp(controller: controller),
    ),
  );
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
        locale: const Locale('th'),
        supportedLocales: const [Locale('th'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        builder: (context, child) {
          final content = MediaQuery(
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
            child: child ?? const SizedBox.shrink(),
          );

          if (!kIsWeb) {
            return content;
          }

          return MeDisWebViewport(child: child ?? const SizedBox.shrink());
        },
        theme: MeDisTheme.light,
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
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          onDestinationSelected: (value) => setState(() => index = value),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.grid_view_outlined),
                selectedIcon: Icon(Icons.grid_view_rounded),
                label: 'เมนู'),
            NavigationDestination(
                icon: Icon(Icons.today_outlined),
                selectedIcon: Icon(Icons.today_rounded),
                label: 'วันนี้'),
            NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person_rounded),
                label: 'โปรไฟล์'),
          ],
        ),
      );
}
