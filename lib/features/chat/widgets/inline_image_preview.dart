import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kohera/core/theme/k_icons.dart';
import 'package:kohera/core/utils/safe_url_launcher.dart';
class InlineImagePreview extends StatelessWidget {
  const InlineImagePreview({
    required this.url,
    required this.isMe,
    super.key,
  });

  final String url;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: GestureDetector(
        onTap: () {
          unawaited(safeLaunchUrl(url));
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(0), // Sharp corners for pixel theme
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260, maxWidth: 280),
            child: Image.network(
              url,
              fit: BoxFit.contain,
              loadingBuilder: (_, child, progress) {
                if (progress == null) return child;
                return Container(
                  height: 80,
                  color: cs.surfaceContainerHighest,
                  child: const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                );
              },
              errorBuilder: (_, _, _) => Container(
                height: 80,
                color: cs.surfaceContainerHighest,
                child: const Center(
                  child: Icon(KIcons.brokenImageOutlined),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
