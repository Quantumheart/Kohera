// Test file uses redundant args for clarity and non-const dynamic values.
// ignore_for_file: avoid_redundant_argument_values
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/e2ee/services/kohera_key_verification.dart';
import 'package:kohera/features/e2ee/widgets/key_verification_inline.dart';
import 'package:matrix/encryption.dart';

import '../helpers/fake_key_verification.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('KeyVerificationInline', () {
    testWidgets('shows Cancel button in waitingAccept state', (tester) async {
      final fake = FakeKeyVerification(state: KeyVerificationState.waitingAccept);
      final kv = KoheraKeyVerification(fake);
      addTearDown(kv.dispose);

      await tester.pumpWidget(wrap(
        KeyVerificationInline(
          verification: kv,
          onDone: (_) {},
          onCancel: () {},
        ),
      ));

      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('shows Accept/Reject in askAccept state', (tester) async {
      final fake = FakeKeyVerification(state: KeyVerificationState/*  */.askAccept);
      final kv = KoheraKeyVerification(fake);
      addTearDown(kv.dispose);

      await tester.pumpWidget(wrap(
        KeyVerificationInline(
          verification: kv,
          onDone: (_) {},
          onCancel: () {},
        ),
      ));

      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Reject'), findsOneWidget);
    });

    testWidgets("shows They match / They don't match in askSas state",
        (tester) async {
      final fake = FakeKeyVerification(state: KeyVerificationState.askSas);
      final kv = KoheraKeyVerification(fake);
      addTearDown(kv.dispose);

      await tester.pumpWidget(wrap(
        KeyVerificationInline(
          verification: kv,
          onDone: (_) {},
          onCancel: () {},
        ),
      ));

      expect(find.text('They match'), findsOneWidget);
      expect(find.text("They don't match"), findsOneWidget);
    });

    testWidgets('shows Done button in done state and calls onDone with true',
        (tester) async {
      final fake = FakeKeyVerification(state: KeyVerificationState.done);
      final kv = KoheraKeyVerification(fake);
      addTearDown(kv.dispose);

      bool? doneResult;
      await tester.pumpWidget(wrap(
        KeyVerificationInline(
          verification: kv,
          onDone: (success) => doneResult = success,
          onCancel: () {},
        ),
      ));

      expect(find.text('Done'), findsOneWidget);

      await tester.tap(find.text('Done'));
      await tester.pump();

      expect(doneResult, isTrue);
    });

    testWidgets('cancel button calls verification.cancel and onCancel',
        (tester) async {
      final fake = FakeKeyVerification(state: KeyVerificationState.waitingAccept);
      final kv = KoheraKeyVerification(fake);
      addTearDown(kv.dispose);

      var cancelCalled = false;
      await tester.pumpWidget(wrap(
        KeyVerificationInline(
          verification: kv,
          onDone: (_) {},
          onCancel: () => cancelCalled = true,
        ),
      ));

      await tester.tap(find.text('Cancel'));
      await tester.pump();

      expect(fake.cancelCalled, isTrue);
      expect(cancelCalled, isTrue);
    });

    testWidgets('rebuilds on state change via ChangeNotifier', (tester) async {
      final fake = FakeKeyVerification(state: KeyVerificationState.waitingAccept);
      final kv = KoheraKeyVerification(fake);
      addTearDown(kv.dispose);

      await tester.pumpWidget(wrap(
        KeyVerificationInline(
          verification: kv,
          onDone: (_) {},
          onCancel: () {},
        ),
      ));

      // Initially shows Cancel
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Done'), findsNothing);

      // Simulate state change to done
      fake.simulateStateChange(KeyVerificationState.done);
      await tester.pump();

      // Now shows Done
      expect(find.text('Done'), findsOneWidget);
      expect(find.text('Cancel'), findsNothing);
    });

    testWidgets('shows Close button in error state', (tester) async {
      final fake = FakeKeyVerification(state: KeyVerificationState.error);
      final kv = KoheraKeyVerification(fake);
      addTearDown(kv.dispose);

      await tester.pumpWidget(wrap(
        KeyVerificationInline(
          verification: kv,
          onDone: (_) {},
          onCancel: () {},
        ),
      ));

      expect(find.text('Close'), findsOneWidget);
    });
  });
}
