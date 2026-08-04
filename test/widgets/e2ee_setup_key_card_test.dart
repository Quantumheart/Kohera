import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/e2ee/widgets/setup/setup_key_card.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('E2eeSetupKeyCard', () {
    testWidgets('displays recovery key in monospace selectable text',
        (tester) async {
      await tester.pumpWidget(wrap(
        const E2eeSetupKeyCard(
          recoveryKey: 'ABC-123-DEF-456',
          copied: false,
          onCopy: _noop,
        ),
      ));

      expect(find.text('ABC-123-DEF-456'), findsOneWidget);
      expect(find.byType(SelectableText), findsOneWidget);
      expect(find.text('Save your recovery key'), findsOneWidget);
    });

    testWidgets('shows empty string when recoveryKey is null', (tester) async {
      await tester.pumpWidget(wrap(
        const E2eeSetupKeyCard(
          recoveryKey: null,
          copied: false,
          onCopy: _noop,
        ),
      ));

      // SelectableText with empty string still renders
      expect(find.byType(SelectableText), findsOneWidget);
      final selectable = tester.widget<SelectableText>(find.byType(SelectableText));
      expect(selectable.data, '');
    });

    testWidgets('copy button calls onCopy and writes to clipboard',
        (tester) async {
      String? clipboardText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboardText =
                (call.arguments as Map<String, dynamic>)['text'] as String;
          }
          return null;
        },
      );

      var copied = false;
      await tester.pumpWidget(wrap(
        E2eeSetupKeyCard(
          recoveryKey: 'SECRET-KEY',
          copied: false,
          onCopy: () => copied = true,
        ),
      ));

      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();

      expect(copied, isTrue);
      expect(clipboardText, 'SECRET-KEY');

      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    testWidgets('copy button is disabled when copied is true', (tester) async {
      await tester.pumpWidget(wrap(
        const E2eeSetupKeyCard(
          recoveryKey: 'KEY',
          copied: true,
          onCopy: _noop,
        ),
      ));

      expect(find.text('Copied'), findsOneWidget);
      expect(find.text('Copy'), findsNothing);

      // The button should be disabled (onPressed null)
      final button = tester.widget<TextButton>(
        find.ancestor(of: find.text('Copied'), matching: find.byType(TextButton)),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('copy button is a no-op when recoveryKey is null',
        (tester) async {
      var copyCalled = false;
      await tester.pumpWidget(wrap(
        E2eeSetupKeyCard(
          recoveryKey: null,
          copied: false,
          onCopy: () => copyCalled = true,
        ),
      ));

      // Button is present with 'Copy' text but the handler checks recoveryKey
      expect(find.text('Copy'), findsOneWidget);

      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();

      // onCopy should NOT be called because recoveryKey is null
      expect(copyCalled, isFalse);
    });

    testWidgets('Learn more link is rendered', (tester) async {
      await tester.pumpWidget(wrap(
        const E2eeSetupKeyCard(
          recoveryKey: 'K',
          copied: false,
          onCopy: _noop,
        ),
      ));

      expect(find.text('Learn more about safe storage'), findsOneWidget);
      expect(find.byIcon(Icons.open_in_new), findsOneWidget);
    });

    testWidgets('shows warning about losing key', (tester) async {
      await tester.pumpWidget(wrap(
        const E2eeSetupKeyCard(
          recoveryKey: 'K',
          copied: false,
          onCopy: _noop,
        ),
      ));

      expect(
        find.textContaining("Don't save it in screenshots"),
        findsOneWidget,
      );
    });
  });
}

void _noop() {}