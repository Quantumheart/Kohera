import 'package:flutter/material.dart';

class E2eeSetupManagementPanel extends StatelessWidget {
  const E2eeSetupManagementPanel({
    required this.onShowRecoveryKey,
    required this.onCreateNewKey,
    required this.onDisable,
    super.key,
  });

  final VoidCallback onShowRecoveryKey;
  final VoidCallback onCreateNewKey;
  final VoidCallback onDisable;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, color: cs.primary, size: 64),
          const SizedBox(height: 16),
          Text(
            'Chat backup',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text(
            'Your keys are backed up. Your encrypted messages are '
            'secure and accessible from any device.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          OutlinedButton(
            onPressed: onShowRecoveryKey,
            child: const Text('Show recovery key'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: onCreateNewKey,
            child: const Text('Create new key'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: onDisable,
            child: Text(
              'Disable backup',
              style: TextStyle(color: cs.error),
            ),
          ),
        ],
      ),
    );
  }
}
