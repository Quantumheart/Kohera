import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:kohera/core/theme/kohera_palette.dart';
import 'package:kohera/core/utils/emoji_spans.dart';
import 'package:kohera/core/utils/safe_url_launcher.dart';

/// A text widget that detects URLs and renders them as tappable, styled links.
///
/// [StatefulWidget] so that [TapGestureRecognizer]s created for link spans
/// are properly disposed on rebuild and unmount. A leak of undisposed
/// recognizers on every rebuild was the root cause of progressive memory
/// growth and eventual OOM crashes in rooms with many URL-containing
/// messages and frequent timeline updates.
class LinkableText extends StatefulWidget {
  const LinkableText({
    required this.text, required this.style, required this.isMe, super.key,
    this.maxLines,
    this.overflow,
  });

  final String text;
  final TextStyle? style;
  final bool isMe;

  /// Optional maximum number of lines before truncating.
  final int? maxLines;

  /// How to handle text overflow (defaults to clip).
  final TextOverflow? overflow;

  static final urlRegex = RegExp(
    r'https?://[^\s)<>]+',
    caseSensitive: false,
  );

  /// Strip common trailing punctuation that's unlikely part of the URL.
  static String cleanUrl(String raw) {
    // Remove trailing punctuation that's almost never part of a URL.
    while (raw.isNotEmpty && '.,;:!?\'"'.contains(raw[raw.length - 1])) {
      raw = raw.substring(0, raw.length - 1);
    }
    return raw;
  }

  @override
  State<LinkableText> createState() => _LinkableTextState();
}

class _LinkableTextState extends State<LinkableText> {
  final _recognizers = <TapGestureRecognizer>[];
  List<InlineSpan>? _cachedSpans;
  String? _cachedText;
  TextStyle? _cachedStyle;
  Color? _cachedLinkColor;

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  TapGestureRecognizer _createRecognizer(String url) {
    final recognizer = TapGestureRecognizer()
      ..onTap = () => unawaited(safeLaunchUrl(url));
    _recognizers.add(recognizer);
    return recognizer;
  }

  List<InlineSpan> _buildSpans(Color linkColor) {
    final text = widget.text;
    final style = widget.style;
    final matches = LinkableText.urlRegex.allMatches(text).toList();

    if (matches.isEmpty) {
      return buildEmojiSpans(text, style);
    }

    final spans = <InlineSpan>[];
    var lastEnd = 0;

    for (final match in matches) {
      final rawUrl = match.group(0)!;
      final cleanedUrl = LinkableText.cleanUrl(rawUrl);
      final urlEnd = match.start + cleanedUrl.length;

      // Plain text before this URL.
      if (match.start > lastEnd) {
        spans.addAll(
            buildEmojiSpans(text.substring(lastEnd, match.start), style),);
      }

      // URL span.
      spans.add(TextSpan(
        text: cleanedUrl,
        style: style?.copyWith(
          color: linkColor,
          decoration: TextDecoration.underline,
          decorationColor: linkColor,
        ),
        recognizer: _createRecognizer(cleanedUrl),
      ),);

      lastEnd = urlEnd;
    }

    // Remaining plain text after the last URL.
    if (lastEnd < text.length) {
      spans.addAll(buildEmojiSpans(text.substring(lastEnd), style));
    }

    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final palette = KoheraPalette.of(context);
    final onBubble =
        widget.isMe ? palette.onOwnBubble : palette.onOtherBubble;
    final linkColor = widget.isMe ? onBubble.withValues(alpha: 0.85) : palette.link;

    // Rebuild spans only when inputs actually change.
    if (_cachedSpans == null ||
        _cachedText != widget.text ||
        _cachedStyle != widget.style ||
        _cachedLinkColor != linkColor) {
      _disposeRecognizers();
      _cachedSpans = _buildSpans(linkColor);
      _cachedText = widget.text;
      _cachedStyle = widget.style;
      _cachedLinkColor = linkColor;
    }

    return Text.rich(
      TextSpan(children: _cachedSpans),
      maxLines: widget.maxLines,
      overflow: widget.overflow ?? TextOverflow.clip,
    );
  }
}
