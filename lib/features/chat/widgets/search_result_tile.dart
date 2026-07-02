import 'package:flutter/material.dart';
import 'package:kohera/core/services/client_avatar_resolver.dart';
import 'package:kohera/core/utils/text_highlight.dart';
import 'package:kohera/core/utils/time_format.dart';
import 'package:kohera/features/chat/models/kohera_message_display.dart';
import 'package:kohera/shared/widgets/user_avatar.dart';

// coverage:ignore-start

class SearchResultTile extends StatelessWidget {
  const SearchResultTile({
    required this.message,
    required this.avatarResolver,
    required this.query,
    required this.onTap,
    super.key,
  });

  final KoheraMessageDisplay message;
  final ClientAvatarResolver avatarResolver;
  final String query;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            UserAvatar(
              avatarResolver: avatarResolver,
              avatarUrl: message.senderAvatarUrl,
              userId: message.senderId,
              displayname: message.senderName,
              size: 36,
            ),
            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          message.senderName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        formatRelativeTimestamp(message.timestamp),
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),

                  _buildHighlightedBody(tt, cs),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHighlightedBody(TextTheme tt, ColorScheme cs) {
    final body = message.body;
    final spans = highlightSpans(body, query);

    return RichText(
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        style: tt.bodyMedium?.copyWith(
          color: cs.onSurfaceVariant.withValues(alpha: 0.7),
        ),
        children: spans.map((span) {
          if (span.isMatch) {
            return TextSpan(
              text: span.text,
              style: TextStyle(
                backgroundColor: cs.primaryContainer,
                color: cs.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            );
          }
          return TextSpan(text: span.text);
        }).toList(),
      ),
    );
  }
}
// coverage:ignore-end
