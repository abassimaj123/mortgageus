import 'package:flutter/material.dart';

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
    return GestureDetector(
      onTap: () => showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          content: Text(body, style: const TextStyle(fontSize: 14, height: 1.5)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(left: 4),
        child: Icon(Icons.info_outline, size: iconSize, color: Colors.grey.shade400),
      ),
    );
  }
}
