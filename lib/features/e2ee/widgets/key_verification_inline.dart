import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kohera/features/e2ee/models/kohera_verification_state.dart';
import 'package:kohera/features/e2ee/services/kohera_key_verification.dart';
import 'package:kohera/features/e2ee/widgets/key_verification_content.dart';

class KeyVerificationInline extends StatefulWidget {
  const KeyVerificationInline({
    required this.verification,
    required this.onDone,
    required this.onCancel,
    super.key,
  });

  final KoheraKeyVerification verification;
  final ValueChanged<bool> onDone;
  final VoidCallback onCancel;

  @override
  State<KeyVerificationInline> createState() => _KeyVerificationInlineState();
}

class _KeyVerificationInlineState extends State<KeyVerificationInline> {
  void _handleCancel() {
    unawaited(widget.verification.cancel());
    widget.onCancel();
  }

  void _handleDone() {
    widget.onDone(
      widget.verification.state == KoheraVerificationState.done,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.verification,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KeyVerificationContent(
            verification: widget.verification,
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: buildVerificationActions(
              verification: widget.verification,
              onCancel: _handleCancel,
              onDone: _handleDone,
            ).map((w) => Padding(
              padding: const EdgeInsets.only(left: 8),
              child: w,
            ),).toList(),
          ),
        ],
      ),
    );
  }
}
