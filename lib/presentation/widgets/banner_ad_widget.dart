import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../../core/ads/ad_config.dart';
import '../../main.dart' show adService;
import '../../core/freemium/freemium_service.dart';
import '../../core/services/analytics_service.dart';

class BannerAdWidget extends StatefulWidget {
  const BannerAdWidget({super.key});

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> {
  BannerAd? _banner;
  bool _loaded = false;
  bool _retried = false;

  @override
  void initState() {
    super.initState();
    if (AdConfig.adsEnabled) _loadBanner();
  }

  void _loadBanner() {
    _banner = BannerAd(
      adUnitId: adService.bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, _) {
          ad.dispose();
          if (!mounted) return;
          setState(() {
            _banner = null;
            _loaded = false;
          });
          AnalyticsService.instance.logBannerFailed();
          if (!_retried) {
            _retried = true;
            Future.delayed(const Duration(seconds: 3), () {
              if (mounted) _loadBanner();
            });
          }
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _banner?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!AdConfig.adsEnabled) return const SizedBox.shrink();
    return ValueListenableBuilder<bool>(
      valueListenable: freemiumService.isPremiumNotifier,
      builder: (_, isPremium, __) {
        if (isPremium) return const SizedBox.shrink();
        if (!_loaded || _banner == null) return const SizedBox(height: 50);
        return SizedBox(
          width: _banner!.size.width.toDouble(),
          height: _banner!.size.height.toDouble(),
          child: AdWidget(ad: _banner!),
        );
      },
    );
  }
}
