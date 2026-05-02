import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

const String _recoveryKeyDocsUrl =
    'https://github.com/Quantumheart/Kohera/blob/main/docs/recovery-key-storage.md';

class ShowRecoveryKeyScreen extends StatefulWidget {
  const ShowRecoveryKeyScreen({super.key});

  @override
  State<ShowRecoveryKeyScreen> createState() => _ShowRecoveryKeyScreenState();
}

class _ShowRecoveryKeyScreenState extends State<ShowRecoveryKeyScreen> {
  Future<String?>? _keyFuture;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _keyFuture =
        context.read<MatrixService>().chatBackup.getStoredRecoveryKey();
  }

  Future<void> _openDocs() async {
    await launchUrl(
      Uri.parse(_recoveryKeyDocsUrl),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recovery key')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: FutureBuilder<String?>(
                future: _keyFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final key = snapshot.data;
                  if (key == null || key.isEmpty) {
                    return _buildNoKey();
                  }
                  return _buildKey(key);
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildKey(String key) {
    final cs = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your recovery key',
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
            "— we can't recover it for you.",
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.error,
                ),
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => unawaited(_openDocs()),
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
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              key,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _copied
                  ? null
                  : () {
                      unawaited(
                        Clipboard.setData(ClipboardData(text: key)),
                      );
                      setState(() => _copied = true);
                    },
              icon: Icon(_copied ? Icons.check : Icons.copy, size: 18),
              label: Text(_copied ? 'Copied' : 'Copy'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoKey() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.key_off_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text(
            'No recovery key on this device',
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            "There's no recovery key stored on this device. If you saved "
            'your key elsewhere when you set up backup, you can still use '
            'it. Otherwise, set up chat backup again to generate a new key.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => context.go('/e2ee-setup'),
            child: const Text('Set up chat backup'),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => unawaited(_openDocs()),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('Learn more about safe storage'),
          ),
        ],
      ),
    );
  }
}
