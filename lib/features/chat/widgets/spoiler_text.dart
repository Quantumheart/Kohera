import 'package:flutter/material.dart';

class SpoilerText extends StatefulWidget {
  const SpoilerText({
    required this.child,
    this.reason,
    super.key,
  });

  final InlineSpan child;
  final String? reason;

  @override
  State<SpoilerText> createState() => _SpoilerTextState();
}

class _SpoilerTextState extends State<SpoilerText> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_revealed) {
      return Text.rich(widget.child);
    }

    final reason = widget.reason;
    final defaultStyle = DefaultTextStyle.of(context).style;
    final hintStyle = defaultStyle.copyWith(color: cs.onSurfaceVariant);
    final obscured = (reason != null && reason.isNotEmpty)
        ? reason
        : '█' * widget.child.toPlainText().length.clamp(1, 64);

    return GestureDetector(
      onTap: () => setState(() => _revealed = true),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(0), // Sharp corners for pixel theme
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(obscured, style: hintStyle),
        ),
      ),
    );
  }
}
