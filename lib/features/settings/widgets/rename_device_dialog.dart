import 'package:flutter/material.dart';

// ── Rename device dialog ───────────────────────────────────────

class RenameDeviceDialog extends StatelessWidget {
  const RenameDeviceDialog._(this._initialName);

  final String _initialName;

  /// Shows a rename dialog pre-filled with [initialName], returning the new
  /// name or `null` if cancelled.
  static Future<String?> show(BuildContext context, {required String initialName}) {
    return showDialog<String>(
      context: context,
      builder: (_) => RenameDeviceDialog._(initialName),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = TextEditingController(text: _initialName);
    return AlertDialog(
      title: const Text('Rename device'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Device name',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('Rename'),
        ),
      ],
    );
  }
}
