import 'package:flutter/material.dart';

class InitErrorView extends StatelessWidget {
  const InitErrorView({required this.error, required this.onRetry, super.key});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final message = error.toString();
    final lowerMessage = message.toLowerCase();
    final isDatabaseError = lowerMessage.contains('indexeddb') ||
        lowerMessage.contains('database');
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline, size: 48),
        const SizedBox(height: 16),
        Text(
          'Failed to start Kohera',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
        ),
        if (isDatabaseError)
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Text(
              'This may be caused by your browser blocking\nIndexedDB (e.g. Private Browsing).',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
            ),
          ),
        const SizedBox(height: 16),
        FilledButton.tonalIcon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
        ),
      ],
    );
  }
}
