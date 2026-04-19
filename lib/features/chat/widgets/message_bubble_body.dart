import 'package:flutter/material.dart';
import 'package:kohera/features/chat/widgets/audio_bubble.dart';
import 'package:kohera/features/chat/widgets/density_metrics.dart';
import 'package:kohera/features/chat/widgets/file_bubble.dart';
import 'package:kohera/features/chat/widgets/html_message_text.dart';
import 'package:kohera/features/chat/widgets/image_bubble.dart';
import 'package:kohera/features/chat/widgets/linkable_text.dart';
import 'package:kohera/features/chat/widgets/verification_request_tile.dart';
import 'package:kohera/features/chat/widgets/video_bubble.dart';
import 'package:matrix/matrix.dart';

const _msgtypeServerNotice = 'm.server_notice';

class MessageBubbleBody extends StatelessWidget {
  const MessageBubbleBody({
    required this.event,
    required this.displayEvent,
    required this.bodyText,
    required this.isMe,
    required this.metrics,
    super.key,
  });

  final Event event;
  final Event displayEvent;
  final String bodyText;
  final bool isMe;
  final DensityMetrics metrics;

  @override
  Widget build(BuildContext context) {
    if (event.redacted) return _RedactedBody(event: event, isMe: isMe);
    if (event.messageType == MessageTypes.BadEncrypted) {
      return _BadEncryptedBody(isMe: isMe);
    }
    if (event.messageType == MessageTypes.Image) {
      return ImageBubble(event: event);
    }
    if (event.messageType == MessageTypes.Audio) {
      return AudioBubble(event: event, isMe: isMe);
    }
    if (event.messageType == MessageTypes.Video) {
      return VideoBubble(event: event, isMe: isMe);
    }
    if (event.messageType == MessageTypes.File) {
      return FileBubble(event: event, isMe: isMe);
    }
    if (event.messageType == EventTypes.KeyVerificationRequest) {
      return VerificationRequestTile(event: event);
    }

    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final formattedBody = displayEvent.formattedText;
    final hasHtml = formattedBody.isNotEmpty &&
        displayEvent.content['format'] == 'org.matrix.custom.html';

    final isEmote = displayEvent.messageType == MessageTypes.Emote;
    final isServerNotice = displayEvent.messageType == _msgtypeServerNotice;

    var textStyle = tt.bodyLarge?.copyWith(
      color: isMe ? cs.onPrimary : cs.onSurface,
      fontSize: metrics.bodyFontSize,
      height: metrics.bodyLineHeight,
    );

    if (isEmote) {
      textStyle = textStyle?.copyWith(fontStyle: FontStyle.italic);
    }
    if (isServerNotice) {
      textStyle = textStyle?.copyWith(
        color: isMe ? cs.onPrimary.withValues(alpha: 0.8) : cs.onSurfaceVariant,
      );
    }

    if (hasHtml) {
      final html = isEmote
          ? '* ${_escapeHtml(event.senderFromMemoryOrFallback.calcDisplayname())} '
              '$formattedBody'
          : formattedBody;
      final htmlWidget = HtmlMessageText(
        html: html,
        style: textStyle,
        isMe: isMe,
        room: event.room,
      );
      if (isServerNotice) return _wrapWithServerNoticeIcon(context, htmlWidget);
      return htmlWidget;
    }

    final displayText = isEmote
        ? '* ${event.senderFromMemoryOrFallback.calcDisplayname()} '
            '$bodyText'
        : bodyText;
    final textWidget = LinkableText(
      text: displayText,
      style: textStyle,
      isMe: isMe,
    );
    if (isServerNotice) return _wrapWithServerNoticeIcon(context, textWidget);
    return textWidget;
  }

  Widget _wrapWithServerNoticeIcon(BuildContext context, Widget child) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2, right: 6),
          child: Icon(
            Icons.campaign_outlined,
            size: 16,
            color: isMe
                ? cs.onPrimary.withValues(alpha: 0.8)
                : cs.onSurfaceVariant,
          ),
        ),
        Flexible(child: child),
      ],
    );
  }

  static String _escapeHtml(String input) => input
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
}

class _RedactedBody extends StatelessWidget {
  const _RedactedBody({required this.event, required this.isMe});

  final Event event;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final redactor = event.redactedBecause?.senderId;
    final isSelfRedact = redactor == event.senderId;
    String label;
    if (isMe) {
      label = 'You deleted this message';
    } else if (isSelfRedact) {
      label = 'This message was deleted';
    } else if (redactor != null) {
      final redactorUser = event.room.unsafeGetUserFromMemoryOrFallback(redactor);
      final displayName = redactorUser.displayName ?? redactor;
      label = 'Deleted by $displayName';
    } else {
      label = 'This message was deleted';
    }
    return Text(
      label,
      style: tt.bodyMedium?.copyWith(
        fontStyle: FontStyle.italic,
        color: isMe
            ? cs.onPrimary.withValues(alpha: 0.5)
            : cs.onSurfaceVariant.withValues(alpha: 0.5),
      ),
    );
  }
}

class _BadEncryptedBody extends StatelessWidget {
  const _BadEncryptedBody({required this.isMe});

  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final color = isMe
        ? cs.onPrimary.withValues(alpha: 0.5)
        : cs.onSurfaceVariant.withValues(alpha: 0.5);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.lock_outline, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          'Unable to decrypt this message',
          style: tt.bodyMedium?.copyWith(
            fontStyle: FontStyle.italic,
            color: color,
          ),
        ),
      ],
    );
  }
}
