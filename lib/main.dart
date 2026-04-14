import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/services/analytics_service.dart';
import 'core/services/crashlytics_service.dart';
// Firebase — uncomment after running `flutterfire configure`:
// import 'package:firebase_core/firebase_core.dart';
// import 'core/firebase/firebase_options.dart';
import 'presentation/screens/calculator/calculator_screen.dart';
import 'presentation/screens/amortization/amortization_screen.dart';
import 'presentation/screens/comparator/comparator_screen.dart';
import 'presentation/screens/extra_payments/extra_payments_screen.dart';
import 'presentation/screens/refinance/refinance_screen.dart';
import 'dart:async';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase init — uncomment after adding google-services.json + firebase_options.dart:
  // await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // await CrashlyticsService.instance.init();

  // Analytics: log app open
  await AnalyticsService.instance.log('app_open');

  runApp(const ProviderScope(child: MortgageUSApp()));
}

class MortgageUSApp extends StatelessWidget {
  const MortgageUSApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'MortgageUS',
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    themeMode: ThemeMode.system,
    home: const _SplashWrapper(),
    debugShowCheckedModeBanner: false,
  );
}

// ── Splash overlay ────────────────────────────────────────────────────────────

class _SplashWrapper extends StatefulWidget {
  const _SplashWrapper();
  @override
  State<_SplashWrapper> createState() => _SplashWrapperState();
}

class _SplashWrapperState extends State<_SplashWrapper>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>   _fade;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fade = Tween<double>(begin: 1, end: 0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );

    Timer(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      _ctrl.forward().then((_) {
        if (mounted) setState(() => _done = true);
      });
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return const _MainShell();
    return Stack(children: [
      const _MainShell(),
      FadeTransition(
        opacity: _fade,
        child: Container(
          color: AppTheme.primary,
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/images/app_icon.png',
                width: 120,
                height: 120,
              ),
              const SizedBox(height: 28),
              const Text(
                'MortgageUS',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                  decoration: TextDecoration.none,
                  fontFamily: 'Inter',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Home Loan Calculator',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 14,
                  decoration: TextDecoration.none,
                  fontFamily: 'Inter',
                ),
              ),
            ],
          ),
        ),
      ),
    ]);
  }
}

class _MainShell extends StatefulWidget {
  const _MainShell();
  @override
  State<_MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<_MainShell> {
  int _index = 0;
  final _screens = const [
    CalculatorScreen(),
    AmortizationScreen(),
    ComparatorScreen(),
    ExtraPaymentsScreen(),
    RefinanceScreen(),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(index: _index, children: _screens),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _index,
      onDestinationSelected: (i) => setState(() => _index = i),
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.calculate), label: 'Calculator'),
        NavigationDestination(
          icon: Icon(Icons.table_rows), label: 'Schedule'),
        NavigationDestination(
          icon: Icon(Icons.compare), label: 'Compare'),
        NavigationDestination(
          icon: Icon(Icons.add_circle), label: 'Extra'),
        NavigationDestination(
          icon: Icon(Icons.refresh), label: 'Refi'),
      ],
    ),
  );
}
