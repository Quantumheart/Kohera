import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/utils/confirm_dialog.dart';

void main() {
  group('confirmDialog', () {
    Future<bool> pumpAndConfirm(
      WidgetTester tester, {
      required String tapLabel,
    }) async {
      late bool result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  result = await confirmDialog(
                    context,
                    title: 'Title',
                    message: 'Body',
                    confirmLabel: 'Yes',
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(tapLabel));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('returns true when confirmed', (tester) async {
      expect(await pumpAndConfirm(tester, tapLabel: 'Yes'), isTrue);
    });

    testWidgets('returns false when cancelled', (tester) async {
      expect(await pumpAndConfirm(tester, tapLabel: 'Cancel'), isFalse);
    });
  });
}
