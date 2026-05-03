import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/e2ee/screens/e2ee_setup_screen.dart';

void main() {
  Future<void> pumpHost(
    WidgetTester tester, {
    required void Function(bool) onResult,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  final r = await showRecoveryKeySavedConfirmation(context);
                  onResult(r);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('returns false when "Not yet" tapped', (tester) async {
    bool? result;
    await pumpHost(tester, onResult: (r) => result = r);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Have you saved your recovery key?'), findsOneWidget);

    await tester.tap(find.text('Not yet'));
    await tester.pumpAndSettle();

    expect(result, isFalse);
  });

  testWidgets('returns true when "I\'ve saved it" tapped', (tester) async {
    bool? result;
    await pumpHost(tester, onResult: (r) => result = r);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text("I've saved it"));
    await tester.pumpAndSettle();

    expect(result, isTrue);
  });

  testWidgets('barrier tap does not dismiss dialog', (tester) async {
    bool? result;
    await pumpHost(tester, onResult: (r) => result = r);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    expect(find.text('Have you saved your recovery key?'), findsOneWidget);
    expect(result, isNull);
  });
}
