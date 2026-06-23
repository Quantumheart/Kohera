import 'package:flutter/material.dart';

/// Builds a [PopupMenuItem] with a leading icon and label, matching the app's
/// context-menu row convention (icon size 18, 8px gap). Pass [color] to tint
/// both the icon and label (e.g. for destructive actions).
PopupMenuItem<T> menuItemRow<T>(
  IconData icon,
  String label,
  T value, {
  Color? color,
}) {
  return PopupMenuItem<T>(
    value: value,
    child: Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Text(label, style: color == null ? null : TextStyle(color: color)),
      ],
    ),
  );
}
