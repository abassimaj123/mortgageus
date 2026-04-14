import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/ads/ad_service.dart';
import '../../core/services/ad_free_service.dart';
import '../../core/theme/app_theme.dart';
import '../providers/ad_free_provider.dart';

/// Bottom sheet: watch a rewarded ad for 24 h ad-free.
class RewardAdSheet extends ConsumerStatefulWidget {
  const RewardAdSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const RewardAdSheet(),
  );

  @override
  ConsumerState<RewardAdSheet> createState() => _RewardAdSheetState();
}

class _RewardAdSheetState extends ConsumerState<RewardAdSheet> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    final isAdFree = ref.watch(adFreeProvider);
    final remaining = AdFreeService.instance.remaining;
    final adReady   = AdService.instance.isRewardedReady;

    return Padding(
      padding: EdgeInsets.only(
        left: 24, right: 24, top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // Icon
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isAdFree ? Icons.shield : Icons.shield_outlined,
              size: 34,
              color: isAdFree ? const Color(0xFFD4A017) : AppTheme.primary,
            ),
          ),
          const SizedBox(height: 16),

          const Text('Ad-Free Mode',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),

          // Status line
          if (isAdFree && remaining != null)
            _StatusChip(label: _formatRemaining(remaining))
          else
            Text(
              'Watch a short ad to enjoy 1 hour without ads.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600, height: 1.4),
            ),

          const SizedBox(height: 24),

          // Rewarded ad tile
          _WatchAdTile(
            enabled: adReady && !_loading,
            isAdFree: isAdFree,
            loading: _loading,
            onTap: _watchAd,
          ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<void> _watchAd() async {
    setState(() => _loading = true);
    final earned = await ref.read(adFreeProvider.notifier).unlockWithRewardedAd();
    if (!mounted) return;
    setState(() => _loading = false);
    if (earned) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('1 hour ad-free unlocked!'),
          backgroundColor: AppTheme.accentGood,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ad not available. Try again later.')),
      );
    }
  }

  String _formatRemaining(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60);
    if (m > 0) return 'Ad-free: ${m}m ${s}s remaining';
    return 'Ad-free: ${s}s remaining';
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  const _StatusChip({required this.label});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
    decoration: BoxDecoration(
      color: AppTheme.accentGood.withValues(alpha: 0.12),
      border: Border.all(color: AppTheme.accentGood),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(label,
      style: const TextStyle(
        color: AppTheme.accentGood,
        fontWeight: FontWeight.w600,
        fontSize: 13,
      )),
  );
}

class _WatchAdTile extends StatelessWidget {
  final bool enabled;
  final bool isAdFree;
  final bool loading;
  final VoidCallback onTap;

  const _WatchAdTile({
    required this.enabled,
    required this.isAdFree,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              border: Border.all(
                color: enabled
                    ? AppTheme.primary.withValues(alpha: 0.35)
                    : Colors.grey.shade300,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.play_circle_outline,
                  color: AppTheme.primary, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Text('Watch Short Ad',
                        style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 15)),
                      if (isAdFree) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.accentGood.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text('Active',
                            style: TextStyle(
                              color: AppTheme.accentGood,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            )),
                        ),
                      ],
                    ]),
                    const SizedBox(height: 2),
                    Text('1 hour ad-free — always free',
                      style: TextStyle(
                        color: Colors.grey.shade600, fontSize: 13)),
                  ],
                ),
              ),
              if (loading)
                const SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              else
                Icon(Icons.chevron_right, color: Colors.grey.shade400),
            ]),
          ),
        ),
      ),
    );
  }
}
