import 'package:flutter/material.dart';
import 'package:kohera/features/chat/widgets/inline_image_preview.dart';
import 'package:kohera/features/chat/widgets/link_preview_card.dart';
import 'package:kohera/features/chat/widgets/linkable_text.dart';

class MessageBubbleLinkPreview extends StatefulWidget {
  const MessageBubbleLinkPreview({
    required this.bodyText,
    required this.isMe,
    super.key,
  });

  final String bodyText;
  final bool isMe;

  @override
  State<MessageBubbleLinkPreview> createState() =>
      _MessageBubbleLinkPreviewState();
}

class _MessageBubbleLinkPreviewState extends State<MessageBubbleLinkPreview> {
  String? _cachedPreviewUrl;
  String? _previewUrlBody;

  static String? _extractFirstUrl(String body) {
    for (final match in LinkableText.urlRegex.allMatches(body)) {
      final url = LinkableText.cleanUrl(match.group(0)!);
      final uri = Uri.tryParse(url);
      if (uri != null && uri.host != 'matrix.to') return url;
    }
    return null;
  }

  static bool _isDirectImageUrl(String url) {
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    return path.endsWith('.gif') ||
        path.endsWith('.png') ||
        path.endsWith('.jpg') ||
        path.endsWith('.jpeg') ||
        path.endsWith('.webp');
  }

  @override
  Widget build(BuildContext context) {
    if (_previewUrlBody != widget.bodyText) {
      _previewUrlBody = widget.bodyText;
      _cachedPreviewUrl = _extractFirstUrl(widget.bodyText);
    }
    final url = _cachedPreviewUrl;
    if (url == null) return const SizedBox.shrink();
    if (_isDirectImageUrl(url)) {
      return InlineImagePreview(url: url, isMe: widget.isMe);
    }
    return LinkPreviewCard(url: url, isMe: widget.isMe);
  }
}
