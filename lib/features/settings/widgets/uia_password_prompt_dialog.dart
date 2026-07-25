import 'package:flutter/material.dart';

// ── UIA password prompt dialog ─────────────────────────────────

class UiaPasswordPromptDialog extends StatelessWidget {
  const UiaPasswordPromptDialog._();

  /// Shows a password dialog for UIA authentication, returning the entered
  /// password or `null` if cancelled.
  static Future<String?> show(BuildContext context) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const UiaPasswordPromptDialog._(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final passwordController = TextEditingController();
    return AlertDialog(
      title: const Text('Authentication required'),
      content: TextField(
        controller: passwordController,
        obscureText: true,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Password',
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
          onPressed: () => Navigator.pop(context, passwordController.text),
          child: const Text('Submit'),
        ),
      ],
    );
  }
}
