import 'package:flutter/material.dart';
import 'package:kohera/features/e2ee/widgets/setup/setup_custody_gate.dart';

class E2eeSetupUnlockSection extends StatelessWidget {
  const E2eeSetupUnlockSection({
    required this.recoveryKeyController,
    required this.recoveryKeyError,
    required this.saveToDevice,
    required this.onSaveToDeviceChanged,
    required this.onVerify,
    required this.onCreateNewKey,
    this.enabled = true,
    super.key,
  });

  final TextEditingController recoveryKeyController;
  final String? recoveryKeyError;
  final bool saveToDevice;
  final ValueChanged<bool> onSaveToDeviceChanged;
  final VoidCallback onVerify;
  final VoidCallback onCreateNewKey;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Unlock your backup',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        const Text('Enter your recovery key to restore your message history.'),
        const SizedBox(height: 16),
        TextField(
          controller: recoveryKeyController,
          enabled: enabled,
          decoration: InputDecoration(
            labelText: 'Recovery key',
            errorText: recoveryKeyError,
            border: const OutlineInputBorder(),
          ),
          style: const TextStyle(fontFamily: 'monospace'),
        ),
        const SizedBox(height: 8),
        E2eeSetupCustodyGate(
          saveToDevice: saveToDevice,
          onChanged: enabled ? onSaveToDeviceChanged : null,
        ),
        const SizedBox(height: 4),
        const Divider(),
        const SizedBox(height: 4),
        Center(
          child: OutlinedButton.icon(
            onPressed: enabled ? onVerify : null,
            icon: const Icon(Icons.devices, size: 18),
            label: const Text('Verify with another device'),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: enabled ? onCreateNewKey : null,
            child: const Text('Create new key'),
          ),
        ),
      ],
    );
  }
}
