// coverage:ignore-start

import 'package:flutter/material.dart';
import 'package:kohera/core/utils/text_highlight.dart';
import 'package:kohera/core/utils/time_format.dart';
import 'package:kohera/features/chat/models/kohera_message_display.dart';
import 'package:kohera/features/chat/models/room_search_result.dart';
import 'package:kohera/shared/services/avatar_resolver.dart';
import 'package:kohera/shared/widgets/user_avatar.dart';

class SearchResultTile extends StatelessWidget {
  const SearchResultTile({
    required this.result,
    required this.avatarResolver,
    required this.query,
    required this.onTap,
    this.highlights,
    super.key,
  });

  final RoomSearchResult result;
  final AvatarResolver avatarResolver;
  final String query;
  final VoidCallback onTap;
  final List<String>? highlights;

  List<String> get _highlightTerms => highlights != null && highlights!.isNotEmpty
      ? highlights!
      : [query];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final message = result.message;
    final terms = _highlightTerms;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final ctx in result.contextBefore)
                    _ContextLine(
                      message: ctx,
                      terms: terms,
                      tt: tt,
                      cs: cs,
                    ),
                  _MainHit(
                    message: message,
                    avatarResolver: avatarResolver,
                    terms: terms,
                    tt: tt,
                    cs: cs,
                  ),
                  for (final ctx in result.contextAfter)
                    _ContextLine(
                      message: ctx,
                      terms: terms,
                      tt: tt,
                      cs: cs,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MainHit extends StatelessWidget {
  const _MainHit({
    required this.message,
    required this.avatarResolver,
    required this.terms,
    required this.tt,
    required this.cs,
  });

  final KoheraMessageDisplay message;
  final AvatarResolver avatarResolver;
  final List<String> terms;
  final TextTheme tt;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Row(
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
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            message.senderName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tt.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (message.isEdited) ...[
                          const SizedBox(width: 4),
                          Text(
                            '(edited)',
                            style: tt.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                            ),
                          ),
                        ],
                      ],
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
              _buildBody(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBody() {
    final body = message.body;
    final spans = highlightSpans(body, terms);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_messageIcon != null) ...[
          Icon(_messageIcon, size: 16, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
          const SizedBox(width: 4),
        ],
        Flexible(
          child: RichText(
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
          ),
        ),
      ],
    );
  }

  IconData? get _messageIcon {
    switch (message.messageType) {
      case 'm.image':
        return Icons.image_rounded;
      case 'm.file':
        return Icons.insert_drive_file_rounded;
      case 'm.audio':
        return Icons.audio_file_rounded;
      case 'm.video':
        return Icons.video_file_rounded;
      default:
        return null;
    }
  }
}

class _ContextLine extends StatelessWidget {
  const _ContextLine({
    required this.message,
    required this.terms,
    required this.tt,
    required this.cs,
  });

  final KoheraMessageDisplay message;
  final List<String> terms;
  final TextTheme tt;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final spans = highlightSpans(message.body, terms);

    return Padding(
      padding: const EdgeInsets.only(left: 12, bottom: 2, top: 2),
      child: Opacity(
        opacity: 0.4,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
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
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    ...spans.map((span) {
                      if (span.isMatch) {
                        return TextSpan(
                          text: span.text,
                          style: TextStyle(
                            backgroundColor: cs.primaryContainer,
                            color: cs.onPrimaryContainer,
                          ),
                        );
                      }
                      return TextSpan(text: span.text);
                    }),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// coverage:ignore-end
