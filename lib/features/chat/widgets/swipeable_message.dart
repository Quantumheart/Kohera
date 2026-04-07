import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SwipeableMessage extends StatefulWidget {
  const SwipeableMessage({
    required this.onReply, required this.child, super.key,
  });

  final VoidCallback onReply;
  final Widget child;

  @override
  State<SwipeableMessage> createState() => _SwipeableMessageState();
}

class _SwipeableMessageState extends State<SwipeableMessage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late Animation<double> _snapBack;
  double _dragExtent = 0;
  bool _triggered = false;
  bool _tracking = false;
  Offset? _startPosition;

  static const _triggerThreshold = 64.0;
  static const _maxDrag = 77.0;
  static const _slopThreshold = 8.0;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _snapBack = const AlwaysStoppedAnimation(0);
    _animCtrl.addListener(() {
      setState(() {
        _dragExtent = _snapBack.value;
      });
    });
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent event) {
    _startPosition = event.position;
    _tracking = false;
    _triggered = false;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_startPosition == null) return;
    final delta = event.position - _startPosition!;

    if (!_tracking) {
      if (delta.distance < _slopThreshold) return;
      if (delta.dx.abs() > delta.dy.abs() && delta.dx > 0) {
        _tracking = true;
      } else {
        _startPosition = null;
        return;
      }
    }

    setState(() {
      _dragExtent = delta.dx.clamp(0, _maxDrag);
    });
    if (!_triggered && _dragExtent >= _triggerThreshold) {
      _triggered = true;
      unawaited(HapticFeedback.mediumImpact());
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_tracking && _triggered) {
      widget.onReply();
    }
    _finishDrag();
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _finishDrag();
  }

  void _finishDrag() {
    _startPosition = null;
    if (!_tracking) return;
    _tracking = false;
    _triggered = false;
    _snapBack = Tween<double>(begin: _dragExtent, end: 0)
        .animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut));
    unawaited(_animCtrl.forward(from: 0));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final progress = (_dragExtent / _triggerThreshold).clamp(0.0, 1.0);

    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: Stack(
        children: [
          Positioned.fill(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Opacity(
                  opacity: progress,
                  child: Icon(
                    Icons.reply_rounded,
                    color: cs.primary,
                    size: 24,
                  ),
                ),
              ),
            ),
          ),
          Transform.translate(
            offset: Offset(_dragExtent, 0),
            child: widget.child,
          ),
        ],
      ),
    );
  }
}
