import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/e2ee/services/kohera_key_verification.dart';
import 'package:kohera/features/e2ee/widgets/key_verification_dialog.dart';
import 'package:kohera/shared/widgets/kohera_loader.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

/// A fake [KeyVerification] for testing. We cannot use Mockito because
/// [onUpdate] and [state] are plain fields, not methods.
class FakeKeyVerification extends Fake implements KeyVerification {
  @override
  void Function()? onUpdate;

  @override
  KeyVerificationState state;

  @override
  String? canceledReason;

  @override
  String? canceledCode;

  @override
  bool canceled;

  List<KeyVerificationEmoji> _sasEmojis = [];

  @override
  List<KeyVerificationEmoji> get sasEmojis => _sasEmojis;

  List<int> _sasNumbers = [];

  @override
  List<int> get sasNumbers => _sasNumbers;

  List<String> _sasTypes = [];

  @override
  List<String> get sasTypes => _sasTypes;

  @override
  List<String> possibleMethods = [];

  @override
  QRCode? qrCode;

  bool cancelCalled = false;
  bool acceptVerificationCalled = false;
  bool acceptSasCalled = false;
  bool rejectSasCalled = false;
  String? continueVerificationMethod;

  FakeKeyVerification({
    this.state = KeyVerificationState.waitingAccept,
    this.canceledReason,
    this.canceledCode,
    this.canceled = false,
  });

  void setSasEmojis(List<KeyVerificationEmoji> emojis) {
    _sasEmojis = emojis;
  }

  void setSasNumbers(List<int> numbers) {
    _sasNumbers = numbers;
  }

  void setSasTypes(List<String> types) {
    _sasTypes = types;
  }

  void simulateStateChange(KeyVerificationState newState) {
    state = newState;
    onUpdate?.call();
  }

  @override
  Future<void> cancel([String? code, bool quiet = false]) async {
    cancelCalled = true;
    canceled = true;
    state = KeyVerificationState.error;
  }

  @override
  Future<void> acceptVerification() async {
    acceptVerificationCalled = true;
  }

  @override
  Future<void> acceptSas() async {
    acceptSasCalled = true;
  }

  @override
  Future<void> rejectSas() async {
    rejectSasCalled = true;
  }

  @override
  Future<void> acceptQRScanConfirmation() async {}

  @override
  Future<void> continueVerification(
    String type, {
    Uint8List? qrDataRawBytes,
  }) async {
    continueVerificationMethod = type;
  }

  @override
  Future<void> start() async {}

  @override
  bool get isDone =>
      canceled ||
      {KeyVerificationState.error, KeyVerificationState.done}.contains(state);
}

void main() {
  Widget buildTestApp({required FakeKeyVerification verification}) {
    return MaterialApp(
      theme: ThemeData(splashFactory: InkRipple.splashFactory),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () {
                unawaited(
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => KeyVerificationDialog(
                      verification: KoheraKeyVerification(verification),
                    ),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openDialog(
    WidgetTester tester, {
    required FakeKeyVerification verification,
  }) async {
    await tester.pumpWidget(buildTestApp(verification: verification));
    await tester.tap(find.text('Open'));
    // Use pump() not pumpAndSettle() because CircularProgressIndicator
    // animates indefinitely in spinner states.
    await tester.pump();
  }

  group('KeyVerificationDialog', () {
    testWidgets('shows spinner in waitingAccept state', (tester) async {
      final verification = FakeKeyVerification();
      await openDialog(tester, verification: verification);

      expect(find.byType(KoheraLoader), findsOneWidget);
      expect(
        find.text('Waiting for the other device to accept...'),
        findsOneWidget,
      );
    });

    testWidgets('renders SAS emoji with Semantics labels', (tester) async {
      final verification = FakeKeyVerification(
        state: KeyVerificationState.askSas,
      );
      // KeyVerificationEmoji takes a number index (0-63)
      verification.setSasEmojis([
        KeyVerificationEmoji(0), // Dog
        KeyVerificationEmoji(1), // Cat
      ]);

      await openDialog(tester, verification: verification);

      // Verify Semantics widgets are present with labels
      final semantics = tester.widgetList<Semantics>(find.byType(Semantics));
      final labels = semantics
          .map((s) => s.properties.label)
          .where((l) => l != null && l.isNotEmpty)
          .toList();
      expect(labels, contains('Dog'));
      expect(labels, contains('Cat'));

      // Verify ExcludeSemantics wraps the emoji text (at least 2 from our code)
      expect(find.byType(ExcludeSemantics), findsAtLeast(2));
      expect(find.text('Compare emoji'), findsOneWidget);
    });

    testWidgets('renders decimal SAS when decimal is negotiated', (
      tester,
    ) async {
      final verification = FakeKeyVerification(
        state: KeyVerificationState.askSas,
      );
      verification.setSasTypes(['decimal']);
      verification.setSasNumbers([1234, 5678, 9012]);

      await openDialog(tester, verification: verification);

      // Title and numbers reflect the decimal representation.
      expect(find.text('Compare numbers'), findsOneWidget);
      expect(find.text('1234'), findsOneWidget);
      expect(find.text('5678'), findsOneWidget);
      expect(find.text('9012'), findsOneWidget);

      // The match/reject actions still work for decimal.
      await tester.tap(find.text('They match'));
      expect(verification.acceptSasCalled, isTrue);
    });

    testWidgets('prefers numbers when both emoji and decimal are negotiated', (
      tester,
    ) async {
      final verification = FakeKeyVerification(
        state: KeyVerificationState.askSas,
      );
      verification.setSasTypes(['emoji', 'decimal']);
      verification.setSasEmojis([KeyVerificationEmoji(0)]);
      verification.setSasNumbers([1234, 5678, 9012]);

      await openDialog(tester, verification: verification);

      expect(find.text('Compare numbers'), findsOneWidget);
      expect(find.text('1234'), findsOneWidget);
    });

    testWidgets('falls back to emoji when no numbers are available', (
      tester,
    ) async {
      final verification = FakeKeyVerification(
        state: KeyVerificationState.askSas,
      );
      verification.setSasTypes(['emoji']);
      verification.setSasEmojis([
        KeyVerificationEmoji(0),
        KeyVerificationEmoji(1),
      ]);

      await openDialog(tester, verification: verification);

      expect(find.text('Compare emoji'), findsOneWidget);
    });

    testWidgets('cancel calls verification.cancel() and pops', (tester) async {
      final verification = FakeKeyVerification();
      await openDialog(tester, verification: verification);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(verification.cancelCalled, isTrue);
      // Dialog should be dismissed
      expect(find.byType(KeyVerificationDialog), findsNothing);
    });

    testWidgets('done state pops dialog', (tester) async {
      final verification = FakeKeyVerification(
        state: KeyVerificationState.done,
      );
      await openDialog(tester, verification: verification);

      expect(find.text('Device verified successfully!'), findsOneWidget);

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(find.byType(KeyVerificationDialog), findsNothing);
    });

    testWidgets('error state displays mapped cancel message', (tester) async {
      final verification = FakeKeyVerification(
        state: KeyVerificationState.error,
        canceledCode: 'm.mismatched_sas',
      );
      await openDialog(tester, verification: verification);

      expect(
        find.text("The emoji/numbers didn't match. Verification cancelled."),
        findsOneWidget,
      );
      expect(find.text('Verification failed'), findsOneWidget);
    });

    testWidgets('askSSSS state shows unlocking message', (tester) async {
      final verification = FakeKeyVerification(
        state: KeyVerificationState.askSSSS,
      );
      await openDialog(tester, verification: verification);

      expect(find.text('Unlocking encryption secrets...'), findsOneWidget);
    });

    testWidgets('askChoice shows the QR/emoji chooser when QR is possible', (
      tester,
    ) async {
      final verification = FakeKeyVerification();
      verification.possibleMethods = [EventTypes.Sas, EventTypes.QRScan];

      await openDialog(tester, verification: verification);

      verification.simulateStateChange(KeyVerificationState.askChoice);
      await tester.pump();
      await tester.pump();

      // A chooser is offered instead of auto-selecting a method.
      expect(verification.continueVerificationMethod, isNull);
      expect(find.text('Scan QR code'), findsOneWidget);
      expect(find.text('Compare numbers instead'), findsOneWidget);
    });

    testWidgets('chooser "Compare numbers instead" selects SAS', (
      tester,
    ) async {
      final verification = FakeKeyVerification(
        state: KeyVerificationState.askChoice,
      );
      verification.possibleMethods = [EventTypes.Sas, EventTypes.QRScan];

      await openDialog(tester, verification: verification);
      await tester.pump();

      await tester.tap(find.text('Compare numbers instead'));
      await tester.pump();

      expect(verification.continueVerificationMethod, EventTypes.Sas);
    });

    testWidgets('askChoice auto-selects SAS when QR is not possible', (
      tester,
    ) async {
      final verification = FakeKeyVerification(
        state: KeyVerificationState.askChoice,
      );
      verification.possibleMethods = [EventTypes.Sas];

      await openDialog(tester, verification: verification);
      await tester.pump();

      expect(verification.continueVerificationMethod, EventTypes.Sas);
      expect(find.text('Scan QR code'), findsNothing);
    });

    testWidgets('state transitions update the UI', (tester) async {
      final verification = FakeKeyVerification();
      await openDialog(tester, verification: verification);

      expect(find.text('Verify device'), findsOneWidget);

      // Simulate state change to done
      verification.simulateStateChange(KeyVerificationState.done);
      await tester.pump();

      expect(find.text('Verified'), findsOneWidget);
      expect(find.text('Device verified successfully!'), findsOneWidget);
    });
  });
}
