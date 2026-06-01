import 'package:flutter/material.dart';
import '../../l10n/strings_en.dart';
import '../../l10n/strings_es.dart';
import '../../main.dart' show isSpanishNotifier;
import 'package:calcwise_core/calcwise_core.dart';

class InfoTooltip extends StatelessWidget {
  final String title;
  final String body;
  final double iconSize;

  const InfoTooltip({
    super.key,
    required this.title,
    required this.body,
    this.iconSize = 16,
  });

  @override
  Widget build(BuildContext context) {
    final isEs = isSpanishNotifier.value;
    final AppStrings s = isEs ? AppStringsES() : AppStringsEN();
    return Semantics(
      button: true,
      label: isEs ? 'Información sobre $title' : 'Information about $title',
      hint: isEs ? 'Toca para ver detalles' : 'Double tap for details',
      child: GestureDetector(
        onTap: () => showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(title,
                style: const TextStyle(
                    fontSize: AppTextSize.bodyLg, fontWeight: FontWeight.bold)),
            content: Text(body,
                style:
                    const TextStyle(fontSize: AppTextSize.body, height: 1.5)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(s.ok),
              ),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.only(left: AppSpacing.xs),
          child: Icon(Icons.info_outline,
              size: iconSize, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}
