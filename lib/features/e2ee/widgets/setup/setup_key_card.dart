import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

const String _recoveryKeyDocsUrl =
    'https://github.com/Quantumheart/Kohera/blob/master/docs/recovery-key-storage.md';

class E2eeSetupKeyCard extends StatelessWidget {
  const E2eeSetupKeyCard({
    required this.recoveryKey,
    required this.copied,
    required this.onCopy,
    super.key,
  });

  final String? recoveryKey;
  final bool copied;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Save your recovery key',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        const Text(
          'Save this key in a password manager, or print it and store '
          'the paper somewhere safe.',
        ),
        const SizedBox(height: 8),
        Text(
          "Don't save it in screenshots, unencrypted notes apps, or chat "
          'messages. If you lose this key, your message history is gone '
          "\u2014 we can't recover it for you.",
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: cs.error,
          ),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => unawaited(
              launchUrl(
                Uri.parse(_recoveryKeyDocsUrl),
                mode: LaunchMode.externalApplication,
              ),
            ),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('Learn more about safe storage'),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.zero,
          ),
          child: SelectableText(
            recoveryKey ?? '',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: copied
                ? null
                : () {
                    if (recoveryKey != null) {
                      unawaited(
                        Clipboard.setData(ClipboardData(text: recoveryKey!)),
                      );
                      onCopy();
                    }
                  },
            icon: Icon(copied ? Icons.check : Icons.copy, size: 18),
            label: Text(copied ? 'Copied' : 'Copy'),
          ),
        ),
      ],
    );
  }
}
