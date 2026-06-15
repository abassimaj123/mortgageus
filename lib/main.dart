import 'dart:async';
import 'dart:ui';
import 'package:calcwise_core/calcwise_core.dart'
    hide CrashlyticsService, iapErrorNotifier, PaywallHard;
import 'core/ads/ad_config.dart';
import 'core/db/mortgage_us_database_adapter.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/theme/app_theme.dart';
import 'core/services/analytics_service.dart';
import 'core/services/crashlytics_service.dart';
import 'core/freemium/freemium_service.dart';
import 'core/freemium/iap_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'core/firebase/firebase_options.dart';
import 'presentation/screens/calculator/calculator_screen.dart';
import 'presentation/screens/amortization/amortization_screen.dart';
import 'presentation/screens/comparator/comparator_screen.dart';
import 'presentation/screens/settings/settings_screen.dart';
import 'presentation/screens/tools/tools_screen.dart';
import 'presentation/screens/history/history_screen.dart';
import 'presentation/screens/splash_screen.dart';
import 'l10n/strings_en.dart';
import 'l10n/strings_es.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'presentation/widgets/paywall_hard.dart';

// Global language notifier — false = English, true = Spanish
final ValueNotifier<bool> isSpanishNotifier = ValueNotifier<bool>(false);

// Tab switch notifier — set to tab index to programmatically switch tabs; -1 = no-op
final ValueNotifier<int> tabSwitchNotifier = ValueNotifier<int>(-1);

// Pre-fill notifier — set by Affordability screen to pre-fill Calculator fields
// Keys: 'homePrice', 'downPayment' (dollars), 'rate', 'termYears',
//        'taxRate', 'insurance', 'hoa' (all doubles)
final ValueNotifier<Map<String, double>?> preFillNotifier =
    ValueNotifier<Map<String, double>?>(null);

// Active scenario notifier — set when a pinned scenario is loaded from History.
// Value = {'id': int, 'label': String, 'loanType': String}. null = none active.
final ValueNotifier<Map<String, dynamic>?> activeScenarioNotifier =
    ValueNotifier<Map<String, dynamic>?>(null);

// Paywall session service — centralized, namespaced by appKey
final paywallSession = PaywallSessionService(
  appKey: 'mortgageus',
  hasFullAccess: () => freemiumService.hasFullAccess,
);

// SmartHistory ring buffer + pinned scenarios service
final smartHistoryService = SmartHistoryService(
  db: MortgageUSDatabaseAdapter(),
  freemium: freemiumService,
);

// Ad service — backed by calcwise_core
final adService = CalcwiseAdService(
  config: CalcwiseAdConfig(
    bannerAndroid: AdConfig.bannerAndroid,
    interstitialAndroid: AdConfig.interstitialAndroid,
    rewardedAndroid: AdConfig.rewardedAndroid,
    banneriOS: AdConfig.banneriOS,
    interstitialiOS: AdConfig.interstitialiOS,
    rewardediOS: AdConfig.rewardediOS,
    calcThreshold: AdConfig.calcThreshold,
    cooldownMinutes: AdConfig.cooldownMinutes,
  ),
  freemium: freemiumService,
  analytics: AnalyticsService.instance,
);

// Returns the right strings class
AppStringsEN get strEN => AppStringsEN();
AppStringsES get strES => AppStringsES();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  unawaited(CalcwiseRemoteConfig.initialize());
  await CalcwiseTax.init(remoteFetcher: calcwiseTaxRemoteFetch);
  await CrashlyticsService.init();

  await themeModeService.initialize();
  await freemiumService.initialize();
  // ⚠️ SCREENSHOT MODE — force premium for store captures, revert before release
  if (AdConfig.screenshotMode) {
    freemiumService.isPremiumNotifier.value = true;
    freemiumService.hasFullAccessNotifier.value = true;
  }
  await IAPService.instance.initialize();
  PaywallHard.globalOnPurchase = IAPService.instance.buy;
  await requestCalcwiseConsent();
  if (AdConfig.adsEnabled) await adService.initialize();
  unawaited(MobileAds.instance.updateRequestConfiguration(
    RequestConfiguration(testDeviceIds: ['FD16D4616C3A21C3ACE5E48F8DC9C1DC']),
  ));
  await RateWatchService.instance.init();
  await paywallSession.initialize();

  // Detect system locale and load saved preference
  final locales = PlatformDispatcher.instance.locales;
  final systemLang = locales.isNotEmpty ? locales.first.languageCode : 'en';
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getString('language');
  isSpanishNotifier.value = (saved ?? systemLang) == 'es';

  // Analytics: startup events
  await AnalyticsService.instance.logAppOpen();
  await AnalyticsService.instance.setUserPremium(freemiumService.hasFullAccess);

  CalcwiseAdFooter.configure(
    adService: adService,
    freemium: freemiumService,
    isSpanishNotifier: isSpanishNotifier,
    onGetPremium: () => IAPService.instance.buy(),
    analytics: AnalyticsService.instance,
  );
  CalcwiseRewardAdSheet.configure(
    adService: adService,
    freemium: freemiumService,
    isSpanishNotifier: isSpanishNotifier,
  );
  runApp(const ProviderScope(child: MortgageUSApp()));
}

class MortgageUSApp extends StatelessWidget {
  const MortgageUSApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, isEs, _) {
        return ValueListenableBuilder<ThemeMode>(
          valueListenable: themeModeService.notifier,
          builder: (context, themeMode, child) => MaterialApp(
            title: 'MortgageUS',
            theme: AppTheme.light,
            darkTheme: AppTheme.dark,
            themeMode: themeMode,
            home: const SplashScreen(),
            routes: {
              '/home': (_) => const _MainShell(),
            },
            debugShowCheckedModeBanner: false,
            builder: (context, child) {
              if (!MediaQuery.of(context).disableAnimations) return child!;
              return Theme(
                data: Theme.of(context).copyWith(
                  pageTransitionsTheme: const PageTransitionsTheme(
                    builders: {
                      TargetPlatform.android: _NoAnimPageTransitionsBuilder(),
                      TargetPlatform.iOS: _NoAnimPageTransitionsBuilder(),
                    },
                  ),
                ),
                child: child!,
              );
            },
          ),
        );
      },
    );
  }
}

class _MainShell extends StatefulWidget {
  const _MainShell();
  @override
  State<_MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<_MainShell> {
  int _index = 0;
  bool _wasPremium = false;

  @override
  void initState() {
    super.initState();
    _wasPremium = freemiumService.hasFullAccess;
    freemiumService.isPremiumNotifier.addListener(_onPremiumChange);
    iapErrorNotifier.addListener(_onIapError);
    iapRestoreResultNotifier.addListener(_onRestoreResult);
    tabSwitchNotifier.addListener(_onTabSwitch);
    WidgetsBinding.instance.addPostFrameCallback(
        (_) async => await paywallSession.recordSession());
  }

  @override
  void dispose() {
    freemiumService.isPremiumNotifier.removeListener(_onPremiumChange);
    iapErrorNotifier.removeListener(_onIapError);
    iapRestoreResultNotifier.removeListener(_onRestoreResult);
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
    showIapErrorSnackBar(context, msg);
    iapErrorNotifier.value = null;
  }

  void _onRestoreResult() {
    final result = iapRestoreResultNotifier.value;
    if (result == null || !mounted) return;
    final isEs = isSpanishNotifier.value;
    final msg = result == 'restored'
        ? (isEs ? '¡Premium restaurado!' : 'Premium restored!')
        : (isEs ? 'No hay compras para restaurar.' : 'No purchases to restore.');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
    iapRestoreResultNotifier.value = null;
  }

  void _onPremiumChange() {
    final now = freemiumService.hasFullAccess;
    if (now && !_wasPremium && mounted) {
      showPremiumWelcomeSnackBar(context, isSpanish: isSpanishNotifier.value);
    }
    _wasPremium = now;
    unawaited(AnalyticsService.instance.setUserPremium(now));
  }

  String _tabTitle(int i, bool isEs) {
    if (isEs) {
      final s = AppStringsES();
      switch (i) {
        case 1:
          return s.amortTitle;
        case 2:
          return s.comparatorTitle;
        case 3:
          return s.toolsTitle;
        case 4:
          return s.navHistory;
        default:
          return s.appTitle;
      }
    } else {
      final s = AppStringsEN();
      switch (i) {
        case 1:
          return s.amortTitle;
        case 2:
          return s.comparatorTitle;
        case 3:
          return s.toolsTitle;
        case 4:
          return s.navHistory;
        default:
          return s.appTitle;
      }
    }
  }

  final _screens = const [
    CalculatorScreen(),
    AmortizationScreen(),
    ComparatorScreen(),
    ToolsScreen(),
    HistoryScreen(),
  ];

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: isSpanishNotifier,
        builder: (context, isEs, _) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
            systemNavigationBarColor: Theme.of(context).scaffoldBackgroundColor,
            systemNavigationBarIconBrightness:
                isDark ? Brightness.light : Brightness.dark,
          ));
          final AppStrings s = isEs ? AppStringsES() : AppStringsEN();
          return Scaffold(
            appBar: AppBar(
              title: Text(_tabTitle(_index, isEs)),
              actions: [
                CalcwiseAppBarActions(
                  freemium: freemiumService,
                  session: paywallSession,
                  onSettings: () => Navigator.push(
                    context,
                    PageRouteBuilder<void>(
                      pageBuilder: (_, __, ___) => const SettingsScreen(),
                      transitionsBuilder: (_, anim, __, child) =>
                          FadeTransition(opacity: anim, child: child),
                      transitionDuration: AppDuration.base,
                    ),
                  ),
                  onRewardAd: () => CalcwiseRewardAdSheet.show(context),
                  onPremium: () => PaywallHard.show(context),
                ),
              ],
            ),
            body: Stack(
              fit: StackFit.expand,
              children: List.generate(
                  _screens.length,
                  (i) => IgnorePointer(
                        ignoring: _index != i,
                        child: CalcwiseTabReveal(
                          active: _index == i,
                          child: _screens[i],
                        ),
                      )),
            ),
            bottomNavigationBar: NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) async {
                FocusManager.instance.primaryFocus?.unfocus();
                setState(() => _index = i);
                adService.onAction();
                // Analytics: log which tab was opened
                const _tabNames = [
                  'calculator',
                  'schedule',
                  'comparator',
                  'tools',
                  'history'
                ];
                if (i < _tabNames.length) {
                  AnalyticsService.instance.logTabChanged(_tabNames[i]);
                }
                final trigger = await paywallSession.recordAction();
                if (!mounted) return;
                if (!(ModalRoute.of(context)?.isCurrent ?? false)) return;
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
                    icon: const Icon(Icons.calculate_rounded),
                    selectedIcon: const Icon(Icons.calculate),
                    label: s.navCalculator),
                NavigationDestination(
                    icon: const Icon(Icons.table_rows_rounded),
                    selectedIcon: const Icon(Icons.table_rows),
                    label: s.navSchedule),
                NavigationDestination(
                    icon: const Icon(Icons.compare_rounded),
                    selectedIcon: const Icon(Icons.compare),
                    label: s.navCompare),
                NavigationDestination(
                    icon: const Icon(Icons.build_rounded),
                    selectedIcon: const Icon(Icons.build_rounded),
                    label: s.navTools),
                NavigationDestination(
                    icon: const Icon(Icons.history_rounded),
                    selectedIcon: const Icon(Icons.history),
                    label: s.navHistory),
              ],
            ),
          );
        },
      );
}

class _NoAnimPageTransitionsBuilder extends PageTransitionsBuilder {
  const _NoAnimPageTransitionsBuilder();
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      child;
}
