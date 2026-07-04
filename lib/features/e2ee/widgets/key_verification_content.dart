
import 'package:flutter/material.dart';
import 'package:kohera/features/e2ee/models/kohera_verification_state.dart';
import 'package:kohera/features/e2ee/models/verification_view.dart';
import 'package:kohera/features/e2ee/services/kohera_key_verification.dart';
import 'package:kohera/features/e2ee/widgets/qr_verification_views.dart';
import 'package:kohera/shared/widgets/kohera_loader.dart';

// ── Title ───────────────────────────────────────────────────────

String verificationTitle(KoheraKeyVerification verification) {
  switch (verification.view) {
    case VerificationView.chooser:
      return 'Verify device';
    case VerificationView.showQr:
      return 'Show QR code';
    case VerificationView.scanQr:
      return 'Scan QR code';
    case VerificationView.standard:
      break;
  }
  switch (verification.state) {
    case KoheraVerificationState.askChoice:
    case KoheraVerificationState.waitingAccept:
      return 'Verify device';
    case KoheraVerificationState.askAccept:
      return 'Incoming verification';
    case KoheraVerificationState.askSas:
      return verification.showsSasNumbers ? 'Compare numbers' : 'Compare emoji';
    case KoheraVerificationState.askSSSS:
      return 'Unlocking secrets';
    case KoheraVerificationState.waitingSas:
      return 'Waiting...';
    case KoheraVerificationState.showQRSuccess:
    case KoheraVerificationState.confirmQRScan:
      return 'QR verification';
    case KoheraVerificationState.done:
      return 'Verified';
    case KoheraVerificationState.error:
      return 'Verification failed';
  }
}

// ── Key verification content ────────────────────────────────────

class KeyVerificationContent extends StatelessWidget {
  const KeyVerificationContent({
    required this.verification,
    super.key,
  });

  final KoheraKeyVerification verification;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildContent(context),
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    switch (verification.view) {
      case VerificationView.chooser:
        return _buildChooser(context);
      case VerificationView.showQr:
        return QrCodeView(data: verification.qrDataRawBytes!);
      case VerificationView.scanQr:
        return QrScannerView(onScanned: verification.onQrScanned);
      case VerificationView.standard:
        break;
    }
    switch (verification.state) {
      case KoheraVerificationState.waitingAccept:
        return _buildWaiting('Waiting for the other device to accept...');

      case KoheraVerificationState.askAccept:
        return const Text(
          'Another device is requesting verification. Accept to continue.',
        );

      case KoheraVerificationState.askChoice:
        return _buildWaiting('Starting verification...');

      case KoheraVerificationState.askSas:
        return verification.showsSasNumbers
            ? _buildSasNumbers(context)
            : _buildSasEmoji(context);

      case KoheraVerificationState.askSSSS:
        return _buildWaiting('Unlocking encryption secrets...');

      case KoheraVerificationState.waitingSas:
        return _buildWaiting('Verifying...');

      case KoheraVerificationState.showQRSuccess:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle,
                color: Theme.of(context).colorScheme.primary, size: 64,),
            const SizedBox(height: 16),
            const Text('QR code scanned successfully.'),
          ],
        );

      case KoheraVerificationState.confirmQRScan:
        return const Text(
          'Does the other device show a green checkmark?',
        );

      case KoheraVerificationState.done:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.verified,
                color: Theme.of(context).colorScheme.primary, size: 64,),
            const SizedBox(height: 16),
            const Text('Device verified successfully!'),
          ],
        );

      case KoheraVerificationState.error:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                color: Theme.of(context).colorScheme.error, size: 64,),
            const SizedBox(height: 16),
            Text(
              verification.canceledReason ??
                  'Verification was cancelled or failed.',
              textAlign: TextAlign.center,
            ),
          ],
        );
    }
  }

  Widget _buildWaiting(String message) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const KoheraLoader(),
        const SizedBox(height: 16),
        Text(message),
      ],
    );
  }

  Widget _buildChooser(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Choose how to verify this device.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        if (verification.canScanQr)
          FilledButton.icon(
            onPressed: verification.chooseScanQr,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan QR code'),
          ),
        if (verification.canScanQr) const SizedBox(height: 8),
        if (verification.canShowQr)
          FilledButton.tonalIcon(
            onPressed: verification.chooseShowQr,
            icon: const Icon(Icons.qr_code_2),
            label: const Text('Show QR code'),
          ),
        if (verification.canShowQr) const SizedBox(height: 8),
        if (verification.canCompareSas)
          TextButton.icon(
            onPressed: verification.chooseCompareSas,
            icon: const Icon(Icons.numbers),
            label: const Text('Compare numbers instead'),
          ),
      ],
    );
  }

  Widget _buildSasNumbers(BuildContext context) {
    final numbers = verification.sasNumbers;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Verify that the following numbers appear on both devices, '
          'in the same order:',
        ),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 24,
          runSpacing: 8,
          children: numbers
              .map((n) => Text(
                    '$n',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w600,
                    ),
                  ),)
              .toList(),
        ),
      ],
    );
  }

  Widget _buildSasEmoji(BuildContext context) {
    final emojis = verification.sasEmojis;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Verify that the following emoji appear on both devices, '
          'in the same order:',
        ),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 16,
          runSpacing: 8,
          children: emojis
              .map((e) => Semantics(
                    label: e.name,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ExcludeSemantics(
                          child: Text(e.emoji,
                              style: const TextStyle(fontSize: 32),),
                        ),
                        const SizedBox(height: 4),
                        Text(e.name,
                            style: Theme.of(context).textTheme.bodySmall,),
                      ],
                    ),
                  ),)
              .toList(),
        ),
      ],
    );
  }
}

// ── Action buttons builder ──────────────────────────────────────

List<Widget> buildVerificationActions({
  required KoheraKeyVerification verification,
  required VoidCallback onCancel,
  required VoidCallback onDone,
}) {
  if (verification.view != VerificationView.standard) {
    return [
      TextButton(onPressed: onCancel, child: const Text('Cancel')),
    ];
  }
  switch (verification.state) {
    case KoheraVerificationState.waitingAccept:
    case KoheraVerificationState.askChoice:
    case KoheraVerificationState.askSSSS:
    case KoheraVerificationState.waitingSas:
      return [
        TextButton(onPressed: onCancel, child: const Text('Cancel')),
      ];

    case KoheraVerificationState.askAccept:
      return [
        TextButton(onPressed: onCancel, child: const Text('Reject')),
        FilledButton(
          onPressed: () => verification.acceptVerification(),
          child: const Text('Accept'),
        ),
      ];

    case KoheraVerificationState.askSas:
      return [
        TextButton(
          onPressed: () => verification.rejectSas(),
          child: const Text("They don't match"),
        ),
        FilledButton(
          onPressed: () => verification.acceptSas(),
          child: const Text('They match'),
        ),
      ];

    case KoheraVerificationState.confirmQRScan:
      return [
        TextButton(onPressed: onCancel, child: const Text('No')),
        FilledButton(
          onPressed: () => verification.acceptQRScanConfirmation(),
          child: const Text('Yes'),
        ),
      ];

    case KoheraVerificationState.showQRSuccess:
    case KoheraVerificationState.done:
      return [
        FilledButton(onPressed: onDone, child: const Text('Done')),
      ];

    case KoheraVerificationState.error:
      return [
        FilledButton(onPressed: onCancel, child: const Text('Close')),
      ];
  }
}
