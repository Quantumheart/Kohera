import 'package:flutter/material.dart';
import 'package:kohera/core/theme/k_icons.dart';
import 'package:kohera/features/chat/models/kohera_message_display.dart';
class VerificationRequestTile extends StatelessWidget {
  const VerificationRequestTile({required this.message, super.key});

  final KoheraMessageDisplay message;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(KIcons.verifiedUserOutlined, size: 16, color: cs.primary),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            'Requested verification',
            style: tt.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ],
    );
  }
}
