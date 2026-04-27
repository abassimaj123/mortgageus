import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'ad_service.dart';
import '../theme/app_theme.dart';
import '../freemium/freemium_service.dart';
import '../freemium/iap_service.dart';
import '../freemium/paywall_service.dart';
import '../services/ad_free_service.dart';
import '../../main.dart' show isSpanishNotifier;
import '../../l10n/strings_en.dart';
import '../../l10n/strings_es.dart';

/// Universal monetization footer — replaces BannerAdWidget in every screen.
///
/// Premium  → nothing
/// Rewarded → green ad-free timer only (no banner)
/// Free     → "Watch ad" button + banner ad
class AdFooter extends StatefulWidget {
  const AdFooter({super.key});
  @override
  State<AdFooter> createState() => _AdFooterState();
}

class _AdFooterState extends State<AdFooter> {
  BannerAd? _banner;
  bool      _bannerLoaded = false;
  Timer?    _tick;

  @override
  void initState() {
    super.initState();
    freemiumService.isPremiumNotifier.addListener(_rebuild);
    freemiumService.isRewardedNotifier.addListener(_rebuild);
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    if (freemiumService.showAds) _loadBanner();
  }

  @override
  void dispose() {
    freemiumService.isPremiumNotifier.removeListener(_rebuild);
    freemiumService.isRewardedNotifier.removeListener(_rebuild);
    _tick?.cancel();
    _banner?.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
    // Load banner lazily when user loses premium/rewarded
    if (freemiumService.showAds && _banner == null) _loadBanner();
  }

  void _loadBanner() {
    _banner = BannerAd(
      adUnitId: AdService.bannerId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (mounted) setState(() { _banner = ad as BannerAd; _bannerLoaded = true; });
        },
        onAdFailedToLoad: (ad, _) => ad.dispose(),
      ),
    )..load();
  }

  @override
  Widget build(BuildContext context) {
    // ── Premium: no ads, no UI ──────────────────────────────────────────────
    if (freemiumService.isPremium) return const SizedBox.shrink();

    // ── Rewarded active: timer banner only ──────────────────────────────────
    if (freemiumService.isRewarded) {
      final mins = freemiumService.rewardedMinutesLeft;
      final isEs = isSpanishNotifier.value;
      final label = isEs
          ? 'Sin anuncios — $mins min restantes'
          : 'Ad-free — $mins min remaining';
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 8),
        color: AppTheme.accentGood.withValues(alpha: 0.08),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.timer_outlined, size: 15, color: AppTheme.accentGood),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  color: AppTheme.accentGood,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ]),
      );
    }

    // ── Free tier: watch-ad (session 2+) + premium button + banner ──────────
    return Column(mainAxisSize: MainAxisSize.min, children: [
      _FreeTierRow(),
      if (_bannerLoaded && _banner != null)
        SizedBox(
          width: double.infinity,
          height: _banner!.size.height.toDouble(),
          child: AdWidget(ad: _banner!),
        ),
    ]);
  }
}

// ── Free tier row: watch-ad (session 2+) + prominent Get Premium ─────────────
class _FreeTierRow extends StatefulWidget {
  @override
  State<_FreeTierRow> createState() => _FreeTierRowState();
}

class _FreeTierRowState extends State<_FreeTierRow> {
  bool _loading = false;

  Future<void> _watch() async {
    setState(() => _loading = true);
    final earned = await AdService.instance.showRewarded();
    if (earned) {
      await freemiumService.activateRewarded();
      await AdFreeService.instance.unlockForDuration(const Duration(minutes: 60));
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final primary      = Theme.of(context).colorScheme.primary;
    const gold         = AppTheme.secondary;
    final showRewarded = paywallService.shouldShowRewarded;

    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (_, isEs, __) {
        final dynamic s = isEs ? AppStringsES() : AppStringsEN();
        return Container(
          color: Colors.grey.shade50,
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Row(children: [
            // Watch ad — only session 2+
            if (showRewarded)
              TextButton.icon(
                onPressed: _loading ? null : _watch,
                icon: _loading
                    ? const SizedBox(width: 13, height: 13,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(Icons.play_circle_outline, size: 15, color: primary),
                label: Text(
                  _loading ? s.loading : s.adFreeMinFree,
                  style: TextStyle(fontSize: 11, color: primary),
                ),
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
              ),
            const Spacer(),
            // Get Premium — always prominent
            ElevatedButton.icon(
              onPressed: () => IAPService.instance.buy(),
              icon: const Icon(Icons.workspace_premium, size: 14),
              label: Text(s.getPremiumBtn,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: gold,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                elevation: 0,
              ),
            ),
            const SizedBox(width: 4),
          ]),
        );
      },
    );
  }
}
