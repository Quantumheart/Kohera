import 'package:flutter/material.dart';

/// Convenience helpers on [BuildContext] for common UI actions.
extension ContextExtension on BuildContext {
  /// Shows a simple text [SnackBar] via the nearest [ScaffoldMessenger].
  void showSnack(String message) {
    ScaffoldMessenger.of(this).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
