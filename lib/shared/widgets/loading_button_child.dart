import 'package:flutter/material.dart';

/// A button child that shows a centered spinner while [loading], otherwise
/// renders [child]. Defaults match the app's button spinner (22px, stroke 2.5).
class LoadingButtonChild extends StatelessWidget {
  const LoadingButtonChild({
    required this.loading,
    required this.child,
    this.size = 22,
    this.strokeWidth = 2.5,
    this.color,
    super.key,
  });

  final bool loading;
  final Widget child;
  final double size;
  final double strokeWidth;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    if (!loading) return child;
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(strokeWidth: strokeWidth, color: color),
    );
  }
}
