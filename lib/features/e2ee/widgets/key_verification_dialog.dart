import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kohera/features/e2ee/services/kohera_key_verification.dart';
import 'package:kohera/features/e2ee/widgets/key_verification_content.dart';

class KeyVerificationDialog extends StatefulWidget {
  final KoheraKeyVerification verification;

  const KeyVerificationDialog({
    required this.verification, super.key,
  });

  static Future<bool?> show(
    BuildContext context, {
    required KoheraKeyVerification verification,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => KeyVerificationDialog(verification: verification),
    );
  }

  @override
  State<KeyVerificationDialog> createState() => _KeyVerificationDialogState();
}

class _KeyVerificationDialogState extends State<KeyVerificationDialog> {
  void _cancel() {
    unawaited(widget.verification.cancel());
    Navigator.pop(context, false);
  }

  void _done() {
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.verification,
      builder: (context, _) => AlertDialog(
        title: Text(verificationTitle(widget.verification)),
        content: SizedBox(
          width: 400,
          child: KeyVerificationContent(
            verification: widget.verification,
          ),
        ),
        actions: buildVerificationActions(
          verification: widget.verification,
          onCancel: _cancel,
          onDone: _done,
        ),
      ),
    );
  }
}
