import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/e2ee/widgets/setup/setup_unlock_section.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('E2eeSetupUnlockSection', () {
    testWidgets('displays title, description, and recovery key field',
        (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(wrap(
        E2eeSetupUnlockSection(
          recoveryKeyController: controller,
          recoveryKeyError: null,
          saveToDevice: false,
          onSaveToDeviceChanged: (_) {},
          onVerify: () {},
          onCreateNewKey: () {},
        ),
      ));
      addTearDown(controller.dispose);

      expect(find.text('Unlock your backup'), findsOneWidget);
      expect(find.text('Enter your recovery key to restore your message history.'),
          findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Recovery key'), findsOneWidget);
    });

    testWidgets('shows error text when recoveryKeyError is set', (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(wrap(
        E2eeSetupUnlockSection(
          recoveryKeyController: controller,
          recoveryKeyError: 'Invalid key',
          saveToDevice: false,
          onSaveToDeviceChanged: (_) {},
          onVerify: () {},
          onCreateNewKey: () {},
        ),
      ));
      addTearDown(controller.dispose);

      expect(find.text('Invalid key'), findsOneWidget);
    });

    testWidgets('Verify button calls onVerify', (tester) async {
      final controller = TextEditingController();
      var verifyCalled = false;
      await tester.pumpWidget(wrap(
        E2eeSetupUnlockSection(
          recoveryKeyController: controller,
          recoveryKeyError: null,
          saveToDevice: false,
          onSaveToDeviceChanged: (_) {},
          onVerify: () => verifyCalled = true,
          onCreateNewKey: () {},
        ),
      ));
      addTearDown(controller.dispose);

      await tester.tap(find.text('Verify with another device'));
      await tester.pumpAndSettle();

      expect(verifyCalled, isTrue);
    });

    testWidgets('Create new key button calls onCreateNewKey', (tester) async {
      final controller = TextEditingController();
      var createCalled = false;
      await tester.pumpWidget(wrap(
        E2eeSetupUnlockSection(
          recoveryKeyController: controller,
          recoveryKeyError: null,
          saveToDevice: false,
          onSaveToDeviceChanged: (_) {},
          onVerify: () {},
          onCreateNewKey: () => createCalled = true,
        ),
      ));
      addTearDown(controller.dispose);

      await tester.tap(find.text('Create new key'));
      await tester.pumpAndSettle();

      expect(createCalled, isTrue);
    });

    testWidgets('save-to-device checkbox toggles via onSaveToDeviceChanged',
        (tester) async {
      final controller = TextEditingController();
      bool? lastValue;
      await tester.pumpWidget(wrap(
        E2eeSetupUnlockSection(
          recoveryKeyController: controller,
          recoveryKeyError: null,
          saveToDevice: false,
          onSaveToDeviceChanged: (v) => lastValue = v,
          onVerify: () {},
          onCreateNewKey: () {},
        ),
      ));
      addTearDown(controller.dispose);

      await tester.tap(find.text('Also keep a copy on this device'));
      await tester.pumpAndSettle();

      expect(lastValue, isTrue);
    });

    testWidgets('all interactive elements disabled when enabled is false',
        (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(wrap(
        E2eeSetupUnlockSection(
          recoveryKeyController: controller,
          recoveryKeyError: null,
          saveToDevice: false,
          onSaveToDeviceChanged: (_) {},
          onVerify: () {},
          onCreateNewKey: () {},
          enabled: false,
        ),
      ));
      addTearDown(controller.dispose);

      // Verify button disabled
      final verifyBtn = tester.widget<OutlinedButton>(
        find.ancestor(
            of: find.text('Verify with another device'),
            matching: find.byType(OutlinedButton)),
      );
      expect(verifyBtn.onPressed, isNull);

      // Create new key disabled
      final createBtn = tester.widget<TextButton>(
        find.ancestor(
            of: find.text('Create new key'), matching: find.byType(TextButton)),
      );
      expect(createBtn.onPressed, isNull);

      // TextField disabled
      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.enabled, isFalse);
    });
  });
}
