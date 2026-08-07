import 'package:flutter/material.dart';
import 'package:kohera/core/utils/text_highlight.dart';
import 'package:kohera/core/utils/time_format.dart';
import 'package:kohera/features/chat/models/kohera_message_display.dart';
import 'package:kohera/features/chat/models/room_search_result.dart';
import 'package:kohera/shared/services/avatar_resolver.dart';
import 'package:kohera/shared/widgets/user_avatar.dart';

// coverage:ignore-start

/// Maximum number of context messages rendered above and below the hit.
const _maxContextLines = 3;

class SearchResultTile extends StatelessWidget {
  const SearchResultTile({
    required this.result,
    required this.avatarResolver,
    required this.query,
    required this.onTap,
    super.key,
  });

  final RoomSearchResult result;
  final AvatarResolver avatarResolver;
  final String query;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final message = result.message;

    final before = result.contextBefore.take(_maxContextLines).toList();
    final after = result.contextAfter.take(_maxContextLines).toList();

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Context messages before the hit (oldest-first).
            for (final ctx in before) _ContextLine(message: ctx),

            // Main matched message.
            Row(
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
                              color:
                                  cs.onSurfaceVariant.withValues(alpha: 0.5),
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

            // Context messages after the hit (oldest-first).
            for (final ctx in after) _ContextLine(message: ctx),
          ],
        ),
      ),
    );
  }

  Widget _buildHighlightedBody(TextTheme tt, ColorScheme cs) {
    final body = result.message.body;
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

/// A dimmed, single-line context message rendered above or below the main
/// search hit. Shows a small sender name and an ellipsized body, with a
/// subtle left border indent to distinguish it from the matched message.
class _ContextLine extends StatelessWidget {
  const _ContextLine({required this.message});

  final KoheraMessageDisplay message;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: cs.onSurfaceVariant.withValues(alpha: 0.15),
              width: 2,
            ),
          ),
        ),
        padding: const EdgeInsets.only(left: 8),
        child: Opacity(
          opacity: 0.4,
          child: RichText(
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            text: TextSpan(
              style: tt.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
              children: [
                TextSpan(
                  text: '${message.senderName}: ',
                  style: tt.bodySmall?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                TextSpan(text: message.body),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
// coverage:ignore-end
