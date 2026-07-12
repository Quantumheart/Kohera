import 'package:flutter/material.dart';

class E2eeSetupActionsBar extends StatelessWidget {
  const E2eeSetupActionsBar({
    this.secondaryLabel,
    this.onSecondary,
    this.secondaryEnabled = true,
    this.primaryLabel,
    this.onPrimary,
    this.primaryEnabled = true,
    this.primaryBusy = false,
    this.primaryColor,
    super.key,
  });

  final String? secondaryLabel;
  final VoidCallback? onSecondary;
  final bool secondaryEnabled;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final bool primaryEnabled;
  final bool primaryBusy;
  final Color? primaryColor;

  @override
  Widget build(BuildContext context) {
    if (secondaryLabel == null && primaryLabel == null) {
      return const SizedBox.shrink();
    }

    final secondary = secondaryLabel != null
        ? TextButton(
            onPressed: secondaryEnabled ? onSecondary : null,
            child: Text(secondaryLabel!),
          )
        : null;
    final primary = primaryLabel != null
        ? FilledButton(
            onPressed: (primaryEnabled && !primaryBusy) ? onPrimary : null,
            style: primaryColor != null
                ? FilledButton.styleFrom(backgroundColor: primaryColor)
                : null,
            child: primaryBusy
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      Text(primaryLabel!),
                    ],
                  )
                : Text(primaryLabel!),
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
