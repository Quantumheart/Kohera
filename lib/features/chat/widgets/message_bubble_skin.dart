import 'package:flutter/material.dart';
import 'package:kohera/core/theme/kohera_palette.dart';
import 'package:kohera/features/chat/widgets/density_metrics.dart';

BorderRadius bubbleRadii({
  required bool isMe,
  required bool isFirst,
  required double radius,
}) {
  final r = Radius.circular(radius);
  // Sharp corners everywhere — no rounded tail for pixel theme
  final tail = Radius.circular(radius);
  return BorderRadius.only(
    topLeft: r,
    topRight: r,
    bottomLeft: isMe ? r : (isFirst ? tail : r),
    bottomRight: isMe ? (isFirst ? tail : r) : r,
  );
}

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
    final palette = KoheraPalette.of(context);
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
              color: isMe ? palette.ownBubble : palette.otherBubble,
              border: Border.all(
                color: palette.borderStrong,
                width: palette.borderWidth,
              ),
              borderRadius: bubbleRadii(
                isMe: isMe,
                isFirst: isFirst,
                radius: palette.radius,
              ),
              boxShadow: [
                BoxShadow(
                  color: palette.shadowHard,
                  offset: Offset(palette.shadowOffset, palette.shadowOffset),
                ),
              ],
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

}
