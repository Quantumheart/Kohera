import 'package:flutter/material.dart';

class KoheraStateEventText {
  const KoheraStateEventText({
    required this.icon,
    required this.text,
    required this.timestamp,
    this.replacementRoomId,
  });

  final IconData icon;
  final String text;
  final DateTime timestamp;
  final String? replacementRoomId;

  bool get isTombstone => replacementRoomId != null;
}
