import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:url_launcher/url_launcher.dart';

typedef LinkLauncher = Future<bool> Function(Uri uri);

/// Renders the markdown `body` of a GitHub release using Material You theming.
///
/// Headings, lists, inline code, code blocks, bold/italic, and links are
/// supported. Links open in the platform's external browser by default.
class ReleaseNotesMarkdown extends StatelessWidget {
  const ReleaseNotesMarkdown({
    required this.data,
    super.key,
    this.shrinkWrap = true,
    this.padding = EdgeInsets.zero,
    @visibleForTesting this.linkLauncher,
  });

  final String data;
  final bool shrinkWrap;
  final EdgeInsets padding;

  /// Test seam — overrides the default `url_launcher` call.
  final LinkLauncher? linkLauncher;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MarkdownBody(
      data: data,
      shrinkWrap: shrinkWrap,
      selectable: true,
      onTapLink: (text, href, title) {
        if (href == null) return;
        final uri = Uri.tryParse(href);
        if (uri == null) return;
        final launcher = linkLauncher ??
            (u) => launchUrl(u, mode: LaunchMode.externalApplication);
        unawaited(launcher(uri));
      },
      styleSheet: _styleSheetFor(theme).copyWith(
        textScaler: MediaQuery.textScalerOf(context),
      ),
    );
  }
}

MarkdownStyleSheet _styleSheetFor(ThemeData theme) {
  final colors = theme.colorScheme;
  final text = theme.textTheme;
  final codeBg = colors.surfaceContainerHighest;
  final codeStyle = (text.bodyMedium ?? const TextStyle()).copyWith(
    fontFamily: 'monospace',
    color: colors.onSurface,
    backgroundColor: codeBg,
  );

  return MarkdownStyleSheet.fromTheme(theme).copyWith(
    a: TextStyle(
      color: colors.primary,
      decoration: TextDecoration.underline,
      decorationColor: colors.primary,
    ),
    p: text.bodyMedium,
    h1: text.headlineSmall?.copyWith(fontWeight: FontWeight.w600),
    h2: text.titleLarge?.copyWith(fontWeight: FontWeight.w600),
    h3: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    h4: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
    code: codeStyle,
    codeblockDecoration: BoxDecoration(
      color: codeBg,
      borderRadius: BorderRadius.circular(8),
    ),
    codeblockPadding: const EdgeInsets.all(12),
    blockquote: text.bodyMedium?.copyWith(
      color: colors.onSurfaceVariant,
      fontStyle: FontStyle.italic,
    ),
    blockquoteDecoration: BoxDecoration(
      border: Border(
        left: BorderSide(color: colors.outlineVariant, width: 4),
      ),
    ),
    blockquotePadding: const EdgeInsets.only(left: 12, top: 4, bottom: 4),
    listBullet: text.bodyMedium,
  );
}
