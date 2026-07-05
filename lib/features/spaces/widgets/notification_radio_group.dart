import 'package:flutter/material.dart';
import 'package:kohera/features/spaces/models/kohera_push_rule_state.dart';

/// Reusable radio-button group for selecting a [KoheraPushRuleState].
///
/// Used in both the space context-menu dialog and the space details panel.
/// Pass [onChanged] as `null` to disable interaction (tiles appear dimmed).
class NotificationRadioGroup extends StatelessWidget {
  const NotificationRadioGroup({
    required this.groupValue, super.key,
    this.onChanged,
  });

  final KoheraPushRuleState groupValue;
  final ValueChanged<KoheraPushRuleState?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    Widget group = RadioGroup<KoheraPushRuleState>(
      groupValue: groupValue,
      onChanged: onChanged ?? (_) {},
      child: const Column(
        children: [
          RadioListTile<KoheraPushRuleState>(
            title: Text('All messages'),
            value: KoheraPushRuleState.notify,
          ),
          RadioListTile<KoheraPushRuleState>(
            title: Text('Mentions only'),
            value: KoheraPushRuleState.mentionsOnly,
          ),
          RadioListTile<KoheraPushRuleState>(
            title: Text('Muted'),
            value: KoheraPushRuleState.dontNotify,
          ),
        ],
      ),
    );
    if (!enabled) {
      group = Opacity(opacity: 0.5, child: AbsorbPointer(child: group));
    }
    return group;
  }
}
