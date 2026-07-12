import 'package:flutter/material.dart';
import 'package:kohera/features/e2ee/services/kohera_key_verification.dart';
import 'package:kohera/features/e2ee/widgets/key_verification_inline.dart';
import 'package:kohera/shared/widgets/kohera_loader.dart';

class E2eeSetupVerifySection extends StatelessWidget {
  const E2eeSetupVerifySection({
    required this.verification,
    required this.onDone,
    required this.onCancel,
    super.key,
  });

  final KoheraKeyVerification? verification;
  final ValueChanged<bool> onDone;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final verification = this.verification;
    if (verification == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const KoheraLoader(),
            const SizedBox(height: 16),
            const Text('Starting verification...'),
            const SizedBox(height: 16),
            TextButton(
              onPressed: onCancel,
              child: const Text('Cancel'),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Verify with another device',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        const Text(
          'Open Kohera on another device and confirm the emoji match.',
        ),
        const SizedBox(height: 24),
        KeyVerificationInline(
          verification: verification,
          onDone: onDone,
          onCancel: onCancel,
        ),
      ],
    );
  }
}
