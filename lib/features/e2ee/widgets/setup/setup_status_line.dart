import 'package:flutter/material.dart';
import 'package:kohera/shared/widgets/kohera_loader.dart';

class E2eeSetupStatusLine extends StatelessWidget {
  const E2eeSetupStatusLine({required this.message, super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const KoheraLoader(),
            const SizedBox(height: 16),
            Text(message),
          ],
        ),
      ),
    );
  }
}
