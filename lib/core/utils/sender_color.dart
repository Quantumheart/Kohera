import 'package:flutter/material.dart';

/// Returns a deterministic colour for a Matrix sender ID, using a mix
/// of the current theme's semantic colours and fixed accent tones.
///
/// When [senderId] is empty, returns [fallback] if provided.
Color senderColor(String senderId, ColorScheme cs, {Color? fallback}) {
  if (senderId.isEmpty && fallback != null) return fallback;
  final hash = senderId.codeUnits.fold<int>(0, (h, c) => h + c);
  final palette = [
    cs.primary,
    cs.tertiary,
    cs.secondary,
    cs.error,
    const Color(0xFF6750A4),
    const Color(0xFFB4846C),
    const Color(0xFF7C9A6E),
    const Color(0xFFC17B5F),
  ];
  return palette[hash % palette.length];
}
