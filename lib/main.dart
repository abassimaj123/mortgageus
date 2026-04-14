import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'presentation/screens/calculator/calculator_screen.dart';
import 'presentation/screens/amortization/amortization_screen.dart';
import 'presentation/screens/comparator/comparator_screen.dart';
import 'presentation/screens/extra_payments/extra_payments_screen.dart';
import 'presentation/screens/refinance/refinance_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
    home: const _MainShell(),
    debugShowCheckedModeBanner: false,
  );
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
