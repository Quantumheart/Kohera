import 'package:flutter/material.dart';

/// A compact vertical icon-over-label action button used in the room and space
/// detail panels. Renders disabled (dimmed) when [onTap] is null.
class DetailActionButton extends StatelessWidget {
  const DetailActionButton({
    required this.icon,
    required this.label,
    this.color,
    this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final effectiveColor = color ?? cs.onSurfaceVariant;
    return InkWell(
      borderRadius: BorderRadius.circular(0), // Sharp corners for pixel theme
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: onTap != null ? effectiveColor : effectiveColor.withValues(alpha: 0.4)),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: onTap != null ? effectiveColor : effectiveColor.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
