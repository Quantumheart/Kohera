import 'package:flutter/material.dart';
import 'package:kohera/features/chat/widgets/density_metrics.dart';

class MessageBubbleSkin extends StatelessWidget {
  const MessageBubbleSkin({
    required this.isMe,
    required this.isFirst,
    required this.metrics,
    required this.child,
    this.reactionBubble,
    super.key,
  });

  final bool isMe;
  final bool isFirst;
  final DensityMetrics metrics;
  final Widget child;
  final Widget? reactionBubble;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final maxWidth = MediaQuery.sizeOf(context).width * 0.72;

    return Stack(
      clipBehavior: Clip.none,
      alignment: isMe
          ? AlignmentDirectional.topEnd
          : AlignmentDirectional.topStart,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: reactionBubble != null ? 22 : 0),
          child: Container(
            constraints: BoxConstraints(maxWidth: maxWidth),
            padding: EdgeInsets.symmetric(
              horizontal: metrics.bubbleHorizontalPad,
              vertical: metrics.bubbleVerticalPad,
            ),
            decoration: BoxDecoration(
              color: isMe
                  ? cs.primary
                  : cs.primaryContainer.withValues(alpha: 0.6),
              borderRadius: _bubbleRadii(),
            ),
            child: child,
          ),
        ),
        if (reactionBubble != null)
          Positioned(
            bottom: 0,
            left: isMe ? null : 12,
            right: isMe ? 12 : null,
            child: reactionBubble!,
          ),
      ],
    );
  }

  BorderRadius _bubbleRadii() {
    final r = Radius.circular(metrics.bubbleRadius);
    const tail = Radius.circular(4);
    return BorderRadius.only(
      topLeft: r,
      topRight: r,
      bottomLeft: isMe ? r : (isFirst ? tail : r),
      bottomRight: isMe ? (isFirst ? tail : r) : r,
    );
  }
}
