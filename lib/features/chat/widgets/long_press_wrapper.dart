import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kohera/features/chat/widgets/swipeable_message.dart' show SwipeableMessage;

/// Detects long press using raw pointer events so it does not participate in
/// the gesture arena and therefore does not interfere with the horizontal drag
/// recogniser in [SwipeableMessage].
///
/// Child widgets that need to handle their own long-press (e.g. reaction chips)
/// can call [LongPressWrapper.claimOf] on pointer-down to prevent this wrapper
/// from firing. Flutter dispatches [Listener] events innermost-first, so the
/// claim is guaranteed to arrive before this wrapper processes the same event.
class LongPressWrapper extends StatefulWidget {
  const LongPressWrapper({required this.onLongPress, required this.child, super.key});

  final void Function(Rect bubbleRect) onLongPress;
  final Widget child;

  /// Suppresses the nearest enclosing [LongPressWrapper] for the current
  /// gesture. No-op when called outside a [LongPressWrapper].
  static void claimOf(BuildContext context) {
    context.getInheritedWidgetOfExactType<_LongPressScope>()?.onClaim();
  }

  @override
  State<LongPressWrapper> createState() => _LongPressWrapperState();
}

class _LongPressScope extends InheritedWidget {
  const _LongPressScope({required this.onClaim, required super.child});
  final VoidCallback onClaim;

  @override
  bool updateShouldNotify(_LongPressScope old) => onClaim != old.onClaim;
}

class _LongPressWrapperState extends State<LongPressWrapper> {
  static const _longPressDuration = Duration(milliseconds: 500);
  static const _touchSlop = 18.0;

  Timer? _timer;
  Offset? _startPosition;
  bool _claimed = false;

  void _claim() {
    _claimed = true;
    _timer?.cancel();
    _timer = null;
  }

  void _onPointerDown(PointerDownEvent event) {
    // An inner Listener (e.g. a reaction chip) may have already claimed this
    // gesture — innermost callbacks fire before outer ones.
    if (_claimed) {
      _claimed = false;
      return;
    }
    _startPosition = event.position;
    _timer?.cancel();
    _timer = Timer(_longPressDuration, () {
      if (!mounted) return;
      unawaited(HapticFeedback.mediumImpact());
      final box = context.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize) {
        final topLeft = box.localToGlobal(Offset.zero);
        final rect = topLeft & box.size;
        widget.onLongPress(rect);
      }
    });
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_startPosition != null &&
        (event.position - _startPosition!).distance > _touchSlop) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    _timer?.cancel();
    _timer = null;
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _LongPressScope(
      onClaim: _claim,
      child: Listener(
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerCancel,
        child: widget.child,
      ),
    );
  }
}
