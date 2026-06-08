import 'package:flutter/material.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:provider/provider.dart';

class ReconnectingBanner extends StatelessWidget {
  const ReconnectingBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final reconnecting = context.select<MatrixService, bool>(
      (s) => s.isReconnecting,
    );

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: reconnecting
          ? const _ReconnectingBannerContent()
          : const SizedBox.shrink(),
    );
  }
}

class _ReconnectingBannerContent extends StatelessWidget {
  const _ReconnectingBannerContent();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Material(
      color: Colors.transparent,
      child: Semantics(
        liveRegion: true,
        label: 'Reconnecting to server',
        child: Container(
          constraints: const BoxConstraints(minHeight: 36),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: cs.onSecondaryContainer, width: 3),
            ),
            color: cs.secondaryContainer,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: cs.onSecondaryContainer,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Reconnecting…',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.bodyMedium?.copyWith(
                    color: cs.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
