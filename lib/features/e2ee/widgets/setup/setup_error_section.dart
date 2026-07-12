import 'package:flutter/material.dart';

class E2eeSetupErrorSection extends StatelessWidget {
  const E2eeSetupErrorSection({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: cs.error, size: 64),
            const SizedBox(height: 16),
            Text(
              message ?? 'An unexpected error occurred during backup setup.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
