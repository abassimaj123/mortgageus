import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/services/analytics_service.dart';
import 'core/services/crashlytics_service.dart';
import 'core/ads/ad_service.dart';
import 'core/freemium/freemium_service.dart';
import 'core/freemium/iap_service.dart';
import 'core/freemium/paywall_service.dart';
import 'presentation/widgets/paywall_soft.dart';
import 'presentation/widgets/paywall_hard.dart';
import 'core/services/ad_free_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'core/firebase/firebase_options.dart';
import 'presentation/screens/calculator/calculator_screen.dart';
import 'presentation/screens/amortization/amortization_screen.dart';
import 'presentation/screens/comparator/comparator_screen.dart';
import 'presentation/screens/settings/settings_screen.dart';
import 'presentation/screens/tools/tools_screen.dart';
import 'presentation/screens/affordability/affordability_screen.dart';
import 'presentation/widgets/reward_ad_sheet.dart';
import 'presentation/providers/ad_free_provider.dart';
import 'l10n/strings_en.dart';
import 'l10n/strings_es.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

// Global language notifier — false = English, true = Spanish
final ValueNotifier<bool> isSpanishNotifier = ValueNotifier<bool>(false);

// Tab switch notifier — set to tab index to programmatically switch tabs; -1 = no-op
final ValueNotifier<int> tabSwitchNotifier = ValueNotifier<int>(-1);

// Pre-fill notifier — set by Affordability screen to pre-fill Calculator fields
// Keys: 'homePrice', 'downPayment' (dollars), 'rate', 'termYears'
final ValueNotifier<Map<String, double>?> preFillNotifier = ValueNotifier<Map<String, double>?>(null);

// Returns the right strings class
AppStringsEN get strEN => AppStringsEN();
AppStringsES get strES => AppStringsES();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await CrashlyticsService.init();

  await AdFreeService.instance.init();
  await freemiumService.initialize();
  await IAPService.instance.initialize();
  await AdService.instance.initialize();
  await paywallService.init();

  // Detect system locale and load saved preference
  final locales = PlatformDispatcher.instance.locales;
  final systemLang = locales.isNotEmpty ? locales.first.languageCode : 'en';
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getString('language');
  isSpanishNotifier.value = (saved ?? systemLang) == 'es';

  // Analytics: startup events
  await AnalyticsService.instance.logAppOpen();
  await AnalyticsService.instance.setUserPremium(freemiumService.isPremium);

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
      _ctrl.forward().then((_) async {
        if (!mounted) return;
        setState(() => _done = true);
        // Record session — no immediate paywall, triggered after user interacts
        await paywallService.recordSession();
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
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(12),
                child: Image.asset(
                  'assets/images/app_icon.png',
                  width: 96,
                  height: 96,
                ),
              ),
              const SizedBox(height: 28),
              ValueListenableBuilder<bool>(
                valueListenable: isSpanishNotifier,
                builder: (_, isEs, __) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('MortgageUS',
                      style: TextStyle(color: Colors.white, fontSize: 32,
                        fontWeight: FontWeight.bold, letterSpacing: 1.2,
                        decoration: TextDecoration.none, fontFamily: 'Inter')),
                    const SizedBox(height: 8),
                    Text(isEs ? AppStringsES().tagline : AppStringsEN().tagline,
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 14, decoration: TextDecoration.none, fontFamily: 'Inter')),
                  ],
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
  int  _index      = 0;
  bool _wasPremium = false;

  @override
  void initState() {
    super.initState();
    _wasPremium = freemiumService.isPremium;
    freemiumService.isPremiumNotifier.addListener(_onPremiumChange);
    iapErrorNotifier.addListener(_onIapError);
    tabSwitchNotifier.addListener(_onTabSwitch);
  }

  @override
  void dispose() {
    freemiumService.isPremiumNotifier.removeListener(_onPremiumChange);
    iapErrorNotifier.removeListener(_onIapError);
    tabSwitchNotifier.removeListener(_onTabSwitch);
    super.dispose();
  }

  void _onTabSwitch() {
    final i = tabSwitchNotifier.value;
    if (i < 0 || !mounted) return;
    setState(() => _index = i);
    tabSwitchNotifier.value = -1;
  }

  void _onIapError() {
    final msg = iapErrorNotifier.value;
    if (msg == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
    iapErrorNotifier.value = null;
  }

  void _onPremiumChange() {
    final now = freemiumService.isPremium;
    if (now && !_wasPremium) {
      AnalyticsService.instance.setUserPremium(true);
    }
    if (now && !_wasPremium && mounted) {
      final isEs = isSpanishNotifier.value;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Row(children: [
          const Icon(Icons.verified_rounded, color: AppTheme.secondary, size: 20),
          const SizedBox(width: 10),
          Text(isEs ? '¡Bienvenido a Premium! Gracias.' : 'Welcome to Premium! Thank you.',
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
        backgroundColor: AppTheme.primary,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
      ));
    }
    _wasPremium = now;
  }

  String _tabTitle(int i, bool isEs) {
    if (isEs) {
      final s = AppStringsES();
      switch (i) {
        case 1: return s.amortTitle;
        case 2: return s.comparatorTitle;
        case 3: return s.affordTitle;
        case 4: return s.toolsTitle;
        default: return s.appTitle;
      }
    } else {
      final s = AppStringsEN();
      switch (i) {
        case 1: return s.amortTitle;
        case 2: return s.comparatorTitle;
        case 3: return s.affordTitle;
        case 4: return s.toolsTitle;
        default: return s.appTitle;
      }
    }
  }

  final _screens = const [
    CalculatorScreen(),
    AmortizationScreen(),
    ComparatorScreen(),
    AffordabilityScreen(),
    ToolsScreen(),
  ];

  @override
  Widget build(BuildContext context) => Consumer(
    builder: (context, ref, _) {
      final isAdFree = ref.watch(adFreeProvider);
      return ValueListenableBuilder<bool>(
        valueListenable: isSpanishNotifier,
        builder: (context, isEs, _) {
          SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
            systemNavigationBarColor: AppTheme.background,
            systemNavigationBarIconBrightness: Brightness.dark,
          ));
          final dynamic s = isEs ? AppStringsES() : AppStringsEN();
          return Scaffold(
        appBar: AppBar(
          title: Text(_tabTitle(_index, isEs)),
          actions: [
            // Rewarded shield — visible only from session 2+
            if (!freemiumService.isPremium && paywallService.shouldShowRewarded)
              IconButton(
                icon: Icon(
                  isAdFree ? Icons.shield : Icons.shield_outlined,
                  color: isAdFree ? AppTheme.secondary : null,
                ),
                tooltip: isEs ? AppStringsES().adFreeActive : AppStringsEN().adFreeActive,
                onPressed: () => RewardAdSheet.show(context),
              ),
            // Premium badge (active) or upgrade button (free)
            ValueListenableBuilder<bool>(
              valueListenable: freemiumService.isPremiumNotifier,
              builder: (_, isPrem, __) => isPrem
                  ? const Padding(
                      padding: EdgeInsets.only(right: 6),
                      child: Tooltip(
                        message: 'Premium active',
                        child: const Icon(Icons.verified_rounded,
                            color: AppTheme.secondary, size: 22),
                      ),
                    )
                  : TextButton.icon(
                      onPressed: () => PaywallSoft.show(context),
                      icon: const Icon(Icons.workspace_premium, size: 16),
                      label: const Text('Premium',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.secondary,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ),
            ),
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              ),
            ),
          ],
        ),
        body: IndexedStack(index: _index, children: _screens),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) {
            setState(() => _index = i);
            AdService.instance.onAction();
            // Analytics: log which tab was opened
            const _tabNames = ['calculator', 'schedule', 'comparator', 'affordability', 'tools'];
            if (i < _tabNames.length) {
              AnalyticsService.instance.logTabChanged(_tabNames[i]);
            }
            final trigger = paywallService.recordAction();
            if (trigger == PaywallTrigger.soft) {
              AnalyticsService.instance.logPaywallShown('soft');
              PaywallSoft.show(context);
            }
            if (trigger == PaywallTrigger.hard) {
              AnalyticsService.instance.logPaywallShown('hard');
              PaywallHard.show(context);
            }
          },
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.calculate_outlined),
              selectedIcon: const Icon(Icons.calculate),
              label: s.navCalculator),
            NavigationDestination(
              icon: const Icon(Icons.table_rows_outlined),
              selectedIcon: const Icon(Icons.table_rows),
              label: s.navSchedule),
            NavigationDestination(
              icon: const Icon(Icons.compare_outlined),
              selectedIcon: const Icon(Icons.compare),
              label: s.navCompare),
            NavigationDestination(
              icon: const Icon(Icons.home_work_outlined),
              selectedIcon: const Icon(Icons.home_work),
              label: s.navAfford),
            NavigationDestination(
              icon: const Icon(Icons.build_outlined),
              selectedIcon: const Icon(Icons.build),
              label: s.navTools),
          ],
        ),
      );
        },
      );
    },
  );
}
