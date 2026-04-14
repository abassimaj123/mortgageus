import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../../core/ads/ad_service.dart';
import '../../core/ads/ad_config.dart';
import '../providers/ad_free_provider.dart';

/// Displays a banner ad at the bottom of a screen.
/// Hides itself when ad-free mode is active or ad fails to load.
class BannerAdWidget extends ConsumerStatefulWidget {
  const BannerAdWidget({super.key});

  @override
  ConsumerState<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends ConsumerState<BannerAdWidget> {
  BannerAd? _banner;
  bool      _loaded = false;

  @override
  void initState() {
    super.initState();
    if (AdConfig.adsEnabled) _loadBanner();
  }

  void _loadBanner() {
    _banner = BannerAd(
      adUnitId: AdService.instance.bannerId,
      size:     AdSize.banner,
      request:  const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded:       (_) => setState(() => _loaded = true),
        onAdFailedToLoad: (ad, _) { ad.dispose(); _banner = null; },
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
    final isAdFree = ref.watch(adFreeProvider);
    if (isAdFree || !_loaded || _banner == null || !AdConfig.adsEnabled) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      width:  _banner!.size.width.toDouble(),
      height: _banner!.size.height.toDouble(),
      child:  AdWidget(ad: _banner!),
    );
  }
}
