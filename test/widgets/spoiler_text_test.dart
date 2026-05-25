import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kohera/features/chat/widgets/spoiler_text.dart';

void main() {
  group('SpoilerText', () {
    testWidgets('hides inner text by default', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SpoilerText(
              child: TextSpan(text: 'secret'),
            ),
          ),
        ),
      );

      expect(find.text('secret'), findsNothing);
    });

    testWidgets('shows reason hint while obscured', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SpoilerText(
              child: TextSpan(text: 'secret'),
              reason: 'plot twist',
            ),
          ),
        ),
      );

      expect(find.text('plot twist'), findsOneWidget);
      expect(find.text('secret'), findsNothing);
    });

    testWidgets('reveals inner text on tap', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SpoilerText(
              child: TextSpan(text: 'secret'),
              reason: 'plot twist',
            ),
          ),
        ),
      );

      await tester.tap(find.byType(SpoilerText));
      await tester.pumpAndSettle();

      expect(find.text('secret'), findsOneWidget);
      expect(find.text('plot twist'), findsNothing);
    });
  });
}
