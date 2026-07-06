import 'package:flutter/material.dart';
import 'package:kohera/core/theme/kohera_palette.dart';
import 'package:kohera/core/utils/emoji_spans.dart';
import 'package:kohera/features/chat/models/kohera_message_display.dart';
import 'package:kohera/features/chat/widgets/density_metrics.dart';
import 'package:kohera/features/chat/widgets/linkable_text.dart';
import 'package:kohera/features/chat/widgets/verification_request_tile.dart';

const _msgtypeServerNotice = 'm.server_notice';
const _msgtypeBadEncrypted = 'm.bad.encrypted';
const _msgtypeEmote = 'm.emote';
const _msgtypeVerificationRequest = 'm.key.verification.request';

/// Font-size multiplier applied to messages containing only emoji.
const _emojiOnlyScale = 2.0;

String escapeHtml(String input) => input
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');

String redactionLabel({
  required bool isMe,
  required String senderId,
  String? redactor,
  String? redactorDisplayName,
}) {
  if (isMe) return 'You deleted this message';
  if (redactor == null) return 'This message was deleted';
  if (redactor == senderId) return 'This message was deleted';
  return 'Deleted by ${redactorDisplayName ?? redactor}';
}

/// Builds the HTML message widget. Provided by the conversion boundary
/// (`ChatMessageItem`) which has access to the SDK `Room` for pill resolution.
typedef HtmlBodyBuilder = Widget Function(String html, TextStyle? style);

class MessageBubbleBody extends StatelessWidget {
  const MessageBubbleBody({
    required this.message,
    required this.isMe,
    required this.metrics,
    required this.htmlBuilder,
    super.key,
  });

  final KoheraMessageDisplay message;
  final bool isMe;
  final DensityMetrics metrics;
  final HtmlBodyBuilder htmlBuilder;

  @override
  Widget build(BuildContext context) {
    if (message.isRedacted) {
      return _RedactedBody(message: message, isMe: isMe);
    }
    if (message.messageType == _msgtypeBadEncrypted) {
      return _BadEncryptedBody(isMe: isMe);
    }
    if (message.messageType == _msgtypeVerificationRequest) {
      return VerificationRequestTile(message: message);
    }

    final palette = KoheraPalette.of(context);
    final tt = Theme.of(context).textTheme;

    final hasHtml = message.formattedHtml != null;

    final isEmote = message.messageType == _msgtypeEmote;
    final isServerNotice = message.messageType == _msgtypeServerNotice;

    final onBubble = isMe ? palette.onOwnBubble : palette.onOtherBubble;

    var textStyle = tt.bodyLarge?.copyWith(
      color: onBubble,
      fontSize: metrics.bodyFontSize,
      height: metrics.bodyLineHeight,
    );

    if (isEmote) {
      textStyle = textStyle?.copyWith(fontStyle: FontStyle.italic);
    }
    if (isServerNotice) {
      textStyle = textStyle?.copyWith(
        color: onBubble.withValues(alpha: 0.8),
      );
    }
    if (!isEmote && !isServerNotice && isEmojiOnly(message.body)) {
      textStyle = textStyle?.copyWith(
        fontSize: (textStyle.fontSize ?? metrics.bodyFontSize) * _emojiOnlyScale,
      );
    }

    if (hasHtml) {
      final html = isEmote
          ? '* ${escapeHtml(message.senderName)} '
              '${message.formattedHtml}'
          : message.formattedHtml!;
      final htmlWidget = htmlBuilder(html, textStyle);
      if (isServerNotice) return _wrapWithServerNoticeIcon(context, htmlWidget);
      return htmlWidget;
    }

    final displayText = isEmote
        ? '* ${message.senderName} '
            '${message.body}'
        : message.body;
    final textWidget = LinkableText(
      text: displayText,
      style: textStyle,
      isMe: isMe,
    );
    if (isServerNotice) return _wrapWithServerNoticeIcon(context, textWidget);
    return textWidget;
  }

  Widget _wrapWithServerNoticeIcon(BuildContext context, Widget child) {
    final palette = KoheraPalette.of(context);
    final onBubble = isMe ? palette.onOwnBubble : palette.onOtherBubble;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2, right: 6),
          child: Icon(
            Icons.campaign_outlined,
            size: 16,
            color: onBubble.withValues(alpha: 0.8),
          ),
        ),
        Flexible(child: child),
      ],
    );
  }
}

class _RedactedBody extends StatelessWidget {
  const _RedactedBody({required this.message, required this.isMe});

  final KoheraMessageDisplay message;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final palette = KoheraPalette.of(context);
    final tt = Theme.of(context).textTheme;

    final label = redactionLabel(
      isMe: isMe,
      senderId: message.senderId,
      redactor: message.redactorId,
      redactorDisplayName: message.redactorName,
    );
    final onBubble = isMe ? palette.onOwnBubble : palette.onOtherBubble;
    return Text(
      label,
      style: tt.bodyMedium?.copyWith(
        fontStyle: FontStyle.italic,
        color: onBubble.withValues(alpha: 0.5),
      ),
    );
  }
}

class _BadEncryptedBody extends StatelessWidget {
  const _BadEncryptedBody({required this.isMe});

  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final palette = KoheraPalette.of(context);
    final tt = Theme.of(context).textTheme;
    final onBubble = isMe ? palette.onOwnBubble : palette.onOtherBubble;
    final color = onBubble.withValues(alpha: 0.5);
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
