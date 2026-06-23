import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/extensions/context_extension.dart';

void main() {
  group('ContextExtension.showSnack', () {
    testWidgets('shows a SnackBar with the given message', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => context.showSnack('Hello there'),
                child: const Text('tap'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('tap'));
      await tester.pump();

      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Hello there'), findsOneWidget);
    });
  });
}
