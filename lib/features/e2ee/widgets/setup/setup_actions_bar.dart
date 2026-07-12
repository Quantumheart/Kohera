import 'package:flutter/material.dart';

class E2eeSetupActionsBar extends StatelessWidget {
  const E2eeSetupActionsBar({
    this.secondaryLabel,
    this.onSecondary,
    this.primaryLabel,
    this.onPrimary,
    this.primaryEnabled = true,
    this.primaryColor,
    super.key,
  });

  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final bool primaryEnabled;
  final Color? primaryColor;

  @override
  Widget build(BuildContext context) {
    if (secondaryLabel == null && primaryLabel == null) {
      return const SizedBox.shrink();
    }

    final secondary = secondaryLabel != null
        ? TextButton(
            onPressed: onSecondary,
            child: Text(secondaryLabel!),
          )
        : null;
    final primary = primaryLabel != null
        ? FilledButton(
            onPressed: primaryEnabled ? onPrimary : null,
            style: primaryColor != null
                ? FilledButton.styleFrom(backgroundColor: primaryColor)
                : null,
            child: Text(primaryLabel!),
          )
        : null;

    if (secondary != null && primary != null) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [secondary, primary],
      );
    }
    return Row(
      mainAxisAlignment: primary != null
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      children: [(secondary ?? primary!)],
    );
  }
}
