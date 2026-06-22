import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/e2ee/widgets/qr_verification_views.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() {
  group('qrScanSupported', () {
    tearDown(() => debugDefaultTargetPlatformOverride = null);

    for (final platform in [
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.macOS,
    ]) {
      test('is true on $platform', () {
        debugDefaultTargetPlatformOverride = platform;
        expect(qrScanSupported, isTrue);
      });
    }

    for (final platform in [
      TargetPlatform.linux,
      TargetPlatform.windows,
      TargetPlatform.fuchsia,
    ]) {
      test('is false on $platform', () {
        debugDefaultTargetPlatformOverride = platform;
        expect(qrScanSupported, isFalse);
      });
    }
  });

  group('QrCodeView', () {
    testWidgets('renders a QR image and scan instruction', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QrCodeView(
              data: Uint8List.fromList(List<int>.generate(32, (i) => i)),
            ),
          ),
        ),
      );

      expect(find.byType(QrImageView), findsOneWidget);
      expect(find.text('Scan this code with your other device.'),
          findsOneWidget,);
    });
  });
}
