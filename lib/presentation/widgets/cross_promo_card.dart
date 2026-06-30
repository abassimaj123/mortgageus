import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:calcwise_core/calcwise_core.dart';
import '../../main.dart' show isSpanishNotifier;

/// Cross-promo banner: promotes Salary Calculator to free MortgageUS users.
/// Dismissible · re-shown after 7 days · hidden for premium users.
class CrossPromoCard extends StatefulWidget {
  final bool isPremium;
  const CrossPromoCard({super.key, required this.isPremium});

  @override
  State<CrossPromoCard> createState() => _CrossPromoCardState();
}

class _CrossPromoCardState extends State<CrossPromoCard> {
  bool _dismissed = false;
  bool _checked = false;

  static const _prefKey = 'xpromo_mortgageus_salary';
  static const _targetName = 'Salary Calculator';
  static const _tagline = 'Know your real take-home pay';
  static const _targetId = 'com.calcwise.salaryapp';
  static const _color = Color(0xFF0B5C2E);

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final p = await SharedPreferences.getInstance();
    final ts = p.getInt(_prefKey) ?? 0;
    final age = DateTime.now().millisecondsSinceEpoch - ts;
    if (mounted)
      setState(() {
        _dismissed = age < 7 * 24 * 3600 * 1000;
        _checked = true;
      });
  }

  Future<void> _dismiss() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_prefKey, DateTime.now().millisecondsSinceEpoch);
    if (mounted) setState(() => _dismissed = true);
  }

  Future<void> _open() async {
    final uri =
        Uri.parse('https://play.google.com/store/apps/details?id=$_targetId');
    if (await canLaunchUrl(uri))
      await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked || _dismissed || widget.isPremium)
      return const SizedBox.shrink();
    final ct = CalcwiseTheme.of(context);
    return Container(
      margin:
          const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: 6),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.06),
        border: Border.all(color: _color.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppRadius.mdPlus),
          ),
          child: const Icon(Icons.attach_money, color: _color, size: 22),
        ),
        const SizedBox(width: AppSpacing.smPlus),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                  color: _color,
                  borderRadius: BorderRadius.circular(AppRadius.xs)),
              child: const Text('CalqWise',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: AppTextSize.xxs,
                      fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: AppRadius.sm),
            Text(isSpanishNotifier.value ? 'También de nosotros' : 'Also from us',
                style: TextStyle(
                    fontSize: AppTextSize.xs, color: ct.textSecondary)),
          ]),
          const SizedBox(height: AppSpacing.xxs),
          Text(_targetName,
              style: TextStyle(
                  fontSize: AppTextSize.md,
                  fontWeight: FontWeight.w600,
                  color: ct.textPrimary)),
          Text(isSpanishNotifier.value ? 'Conoce tu sueldo neto real' : _tagline,
              style:
                  TextStyle(fontSize: AppTextSize.xs, color: ct.textSecondary)),
        ])),
        const SizedBox(width: AppSpacing.sm),
        Column(children: [
          IconButton(
            onPressed: _dismiss,
            tooltip: isSpanishNotifier.value ? 'Descartar' : 'Dismiss',
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            padding: EdgeInsets.zero,
            icon:
                Icon(Icons.close_rounded, size: 16, color: ct.textSecondary),
          ),
          const SizedBox(height: AppSpacing.sm),
          InkWell(
              onTap: _open,
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.smPlus, vertical: 5),
                decoration: BoxDecoration(
                    color: _color,
                    borderRadius: BorderRadius.circular(AppRadius.md)),
                child: Text(isSpanishNotifier.value ? 'Gratis' : 'Free',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: AppTextSize.xs,
                        fontWeight: FontWeight.bold)),
              )),
        ]),
      ]),
    );
  }
}
