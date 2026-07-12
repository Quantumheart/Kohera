import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/theme/kohera_theme.dart';
import 'package:kohera/features/chat/models/kohera_poll_draft.dart';
import 'package:kohera/features/chat/widgets/create_poll_dialog.dart';

Widget _harness() => MaterialApp(
      theme: KoheraTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => CreatePollDialog.show(context),
            child: const Text('open'),
          ),
        ),
      ),
    );

Future<void> _fillOption(WidgetTester tester, int index, String text) async {
  await tester.enterText(find.widgetWithText(TextField, 'Option $index'), text);
}

void main() {
  testWidgets('blocks send when question is empty', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a question.'), findsOneWidget);
  });

  testWidgets('blocks send when an option is empty', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Question'), 'Tea?');
    await _fillOption(tester, 1, 'Yes');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(find.text('All options must have text.'), findsOneWidget);
  });

  testWidgets('blocks send when options are duplicated', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Question'), 'Tea?');
    await _fillOption(tester, 1, 'Yes');
    await _fillOption(tester, 2, 'Yes');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(find.text('Options must be unique.'), findsOneWidget);
  });

  testWidgets('can add and remove options within 2–20 bounds', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Option 1'), findsOneWidget);
    expect(find.text('Option 2'), findsOneWidget);

    await tester.tap(find.text('Add option'));
    await tester.pumpAndSettle();
    expect(find.text('Option 3'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove option').first);
    await tester.pumpAndSettle();
    expect(find.text('Option 3'), findsNothing);
  });

  testWidgets('returns a single-select disclosed draft on valid submit',
      (tester) async {
    KoheraPollDraft? result;
    await tester.pumpWidget(MaterialApp(
      theme: KoheraTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await CreatePollDialog.show(context);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Question'), 'Tea?');
    await _fillOption(tester, 1, 'Yes');
    await _fillOption(tester, 2, 'No');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.question, 'Tea?');
    expect(result!.answers, ['Yes', 'No']);
    expect(result!.disclosed, isTrue);
    expect(result!.maxSelections, 1);
  });

  testWidgets('returns multi-select draft when multi-select toggled',
      (tester) async {
    KoheraPollDraft? result;
    await tester.pumpWidget(MaterialApp(
      theme: KoheraTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await CreatePollDialog.show(context);
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Question'), 'Pick');
    await _fillOption(tester, 1, 'A');
    await _fillOption(tester, 2, 'B');
    await tester.tap(find.text('Allow multiple selections'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.maxSelections, 2);
    expect(result!.disclosed, isTrue);
  });
}
