import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:kohera/features/e2ee/widgets/key_verification_flow.dart';
import 'package:kohera/features/e2ee/widgets/qr_verification_views.dart';
import 'package:kohera/shared/widgets/kohera_loader.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

// ── Title ───────────────────────────────────────────────────────

String verificationTitle(
  KeyVerificationState state,
  VerificationView view,
  KeyVerification verification,
) {
  switch (view) {
    case VerificationView.chooser:
      return 'Verify device';
    case VerificationView.showQr:
      return 'Show QR code';
    case VerificationView.scanQr:
      return 'Scan QR code';
    case VerificationView.standard:
      break;
  }
  switch (state) {
    case KeyVerificationState.askChoice:
    case KeyVerificationState.waitingAccept:
      return 'Verify device';
    case KeyVerificationState.askAccept:
      return 'Incoming verification';
    case KeyVerificationState.askSas:
      return _showsSasNumbers(verification)
          ? 'Compare numbers'
          : 'Compare emoji';
    case KeyVerificationState.askSSSS:
      return 'Unlocking secrets';
    case KeyVerificationState.waitingSas:
      return 'Waiting...';
    case KeyVerificationState.showQRSuccess:
    case KeyVerificationState.confirmQRScan:
      return 'QR verification';
    case KeyVerificationState.done:
      return 'Verified';
    case KeyVerificationState.error:
      return 'Verification failed';
  }
}

bool _showsSasNumbers(KeyVerification verification) {
  final types = verification.sasTypes;
  final decimalNegotiated = types.isEmpty || types.contains('decimal');
  return decimalNegotiated && verification.sasNumbers.isNotEmpty;
}

// ── Key verification content ────────────────────────────────────

class KeyVerificationContent extends StatelessWidget {
  const KeyVerificationContent({
    required this.state,
    required this.verification,
    this.view = VerificationView.standard,
    this.onChooseShowQr,
    this.onChooseScanQr,
    this.onChooseCompareSas,
    this.onScanned,
    super.key,
  });

  final KeyVerificationState state;
  final KeyVerification verification;
  final VerificationView view;
  final VoidCallback? onChooseShowQr;
  final VoidCallback? onChooseScanQr;
  final VoidCallback? onChooseCompareSas;
  final ValueChanged<Uint8List>? onScanned;

  bool get _showSasNumbers => _showsSasNumbers(verification);

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
    switch (view) {
      case VerificationView.chooser:
        return _buildChooser(context);
      case VerificationView.showQr:
        return QrCodeView(
          data: Uint8List.fromList(verification.qrCode!.qrDataRawBytes),
        );
      case VerificationView.scanQr:
        return QrScannerView(onScanned: onScanned ?? (_) {});
      case VerificationView.standard:
        break;
    }
    switch (state) {
      case KeyVerificationState.waitingAccept:
        return _buildWaiting('Waiting for the other device to accept...');

      case KeyVerificationState.askAccept:
        return const Text(
          'Another device is requesting verification. Accept to continue.',
        );

      case KeyVerificationState.askChoice:
        return _buildWaiting('Starting verification...');

      case KeyVerificationState.askSas:
        return _showSasNumbers
            ? _buildSasNumbers(context)
            : _buildSasEmoji(context);

      case KeyVerificationState.askSSSS:
        return _buildWaiting('Unlocking encryption secrets...');

      case KeyVerificationState.waitingSas:
        return _buildWaiting('Verifying...');

      case KeyVerificationState.showQRSuccess:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle,
                color: Theme.of(context).colorScheme.primary, size: 64,),
            const SizedBox(height: 16),
            const Text('QR code scanned successfully.'),
          ],
        );

      case KeyVerificationState.confirmQRScan:
        return const Text(
          'Does the other device show a green checkmark?',
        );

      case KeyVerificationState.done:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.verified,
                color: Theme.of(context).colorScheme.primary, size: 64,),
            const SizedBox(height: 16),
            const Text('Device verified successfully!'),
          ],
        );

      case KeyVerificationState.error:
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
    final canShowQr = verification.possibleMethods.contains(EventTypes.QRShow) &&
        verification.qrCode != null;
    final canScanQr =
        verification.possibleMethods.contains(EventTypes.QRScan) &&
            qrScanSupported;
    final canCompareSas =
        verification.possibleMethods.contains(EventTypes.Sas);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Choose how to verify this device.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        if (canScanQr)
          FilledButton.icon(
            onPressed: onChooseScanQr,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan QR code'),
          ),
        if (canScanQr) const SizedBox(height: 8),
        if (canShowQr)
          FilledButton.tonalIcon(
            onPressed: onChooseShowQr,
            icon: const Icon(Icons.qr_code_2),
            label: const Text('Show QR code'),
          ),
        if (canShowQr) const SizedBox(height: 8),
        if (canCompareSas)
          TextButton.icon(
            onPressed: onChooseCompareSas,
            icon: const Icon(Icons.emoji_symbols),
            label: const Text('Compare emoji instead'),
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
  required KeyVerificationState state,
  required KeyVerification verification,
  required VoidCallback onCancel,
  required VoidCallback onDone,
  VerificationView view = VerificationView.standard,
}) {
  if (view != VerificationView.standard) {
    return [
      TextButton(onPressed: onCancel, child: const Text('Cancel')),
    ];
  }
  switch (state) {
    case KeyVerificationState.waitingAccept:
    case KeyVerificationState.askChoice:
    case KeyVerificationState.askSSSS:
    case KeyVerificationState.waitingSas:
      return [
        TextButton(onPressed: onCancel, child: const Text('Cancel')),
      ];

    case KeyVerificationState.askAccept:
      return [
        TextButton(onPressed: onCancel, child: const Text('Reject')),
        FilledButton(
          onPressed: () => verification.acceptVerification(),
          child: const Text('Accept'),
        ),
      ];

    case KeyVerificationState.askSas:
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

    case KeyVerificationState.confirmQRScan:
      return [
        TextButton(onPressed: onCancel, child: const Text('No')),
        FilledButton(
          onPressed: () => verification.acceptQRScanConfirmation(),
          child: const Text('Yes'),
        ),
      ];

    case KeyVerificationState.showQRSuccess:
    case KeyVerificationState.done:
      return [
        FilledButton(onPressed: onDone, child: const Text('Done')),
      ];

    case KeyVerificationState.error:
      return [
        FilledButton(onPressed: onCancel, child: const Text('Close')),
      ];
  }
}
