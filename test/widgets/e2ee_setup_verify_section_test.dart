import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/e2ee/services/kohera_key_verification.dart';
import 'package:kohera/features/e2ee/widgets/setup/setup_verify_section.dart';
import 'package:kohera/shared/widgets/kohera_loader.dart';
import 'package:matrix/encryption.dart';

import '../helpers/fake_key_verification.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('E2eeSetupVerifySection', () {
    testWidgets('shows loading spinner and Cancel when verification is null',
        (tester) async {
      var cancelCalled = false;
      await tester.pumpWidget(wrap(
        E2eeSetupVerifySection(
          verification: null,
          onDone: (_) {},
          onCancel: () => cancelCalled = true,
        ),
      ));

      expect(find.byType(KoheraLoader), findsOneWidget);
      expect(find.text('Starting verification...'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pump();

      expect(cancelCalled, isTrue);
    });

    testWidgets('shows title and KeyVerificationInline when verification set',
        (tester) async {
      final fake = FakeKeyVerification(state: KeyVerificationState.waitingAccept);
      final kv = KoheraKeyVerification(fake);
      addTearDown(kv.dispose);

      await tester.pumpWidget(wrap(
        E2eeSetupVerifySection(
          verification: kv,
          onDone: (_) {},
          onCancel: () {},
        ),
      ));

      expect(find.text('Verify with another device'), findsOneWidget);
      expect(
        find.text('Open Kohera on another device and confirm the emoji match.'),
        findsOneWidget,
      );
      // KeyVerificationInline is rendered with a Cancel button
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('onCancel is propagated through KeyVerificationInline',
        (tester) async {
      final fake = FakeKeyVerification(state: KeyVerificationState.waitingAccept);
      final kv = KoheraKeyVerification(fake);
      addTearDown(kv.dispose);

      var cancelCalled = false;
      await tester.pumpWidget(wrap(
        E2eeSetupVerifySection(
          verification: kv,
          onDone: (_) {},
          onCancel: () => cancelCalled = true,
        ),
      ));

      await tester.tap(find.text('Cancel'));
      await tester.pump();

      expect(cancelCalled, isTrue);
      expect(fake.cancelCalled, isTrue);
    });

    testWidgets('onDone is propagated with true when verification is done',
        (tester) async {
      final fake = FakeKeyVerification(state: KeyVerificationState.done);
      final kv = KoheraKeyVerification(fake);
      addTearDown(kv.dispose);

      bool? doneResult;
      await tester.pumpWidget(wrap(
        E2eeSetupVerifySection(
          verification: kv,
          onDone: (success) => doneResult = success,
          onCancel: () {},
        ),
      ));

      await tester.tap(find.text('Done'));
      await tester.pump();

      expect(doneResult, isTrue);
    });
  });
}
