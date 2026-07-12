import 'package:flutter/material.dart';
import 'package:kohera/features/e2ee/widgets/setup/setup_bullet_points.dart';

class E2eeSetupExplainer extends StatelessWidget {
  const E2eeSetupExplainer({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'What is key backup?',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        const Text(
          'Your messages are encrypted end-to-end. A recovery key '
          'lets you access them on new devices or if you reinstall.',
        ),
        const SizedBox(height: 24),
        const Text('Without it:'),
        const SizedBox(height: 8),
        const E2eeSetupBulletPoints(
          items: [
            'Message history is lost',
            "Cross-device verification won't work",
            'Some features may not work',
          ],
        ),
      ],
    );
  }
}
