import 'package:flutter/material.dart';

class E2eeSetupCustodyGate extends StatelessWidget {
  const E2eeSetupCustodyGate({
    required this.saveToDevice,
    required this.onChanged,
    super.key,
  });

  final bool saveToDevice;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      value: saveToDevice,
      onChanged: (v) => onChanged(v ?? false),
      title: const Text('Also keep a copy on this device'),
      subtitle: Text(
        'Convenient for unlocking on this device. This is not a '
        'backup \u2014 if you lose the device, this copy is gone too.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
      mouseCursor: SystemMouseCursors.click,
    );
  }
}
