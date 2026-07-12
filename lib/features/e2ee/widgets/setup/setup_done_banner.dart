import 'package:flutter/material.dart';

class E2eeSetupDoneBanner extends StatelessWidget {
  const E2eeSetupDoneBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, color: cs.primary, size: 64),
            const SizedBox(height: 16),
            Text(
              "You're all set!",
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text(
              'Your messages are backed up and will be available '
              'across all your devices.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
