import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/shared/widgets/report_content_dialog.dart';

void main() {
  Future<void> showDialog(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showReportContentDialog(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('submit is disabled until reason is non-empty', (tester) async {
    await showDialog(tester);

    final reportButton = find.text('Report');
    expect(reportButton, findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.ancestor(
        of: reportButton,
        matching: find.byType(FilledButton),
      )).enabled,
      isFalse,
    );

    await tester.enterText(find.byType(TextField), 'spam');
    await tester.pump();

    expect(
      tester.widget<FilledButton>(find.ancestor(
        of: reportButton,
        matching: find.byType(FilledButton),
      )).enabled,
      isTrue,
    );
  });

  testWidgets('returns trimmed reason when submitted', (tester) async {
    String? captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  captured = await showReportContentDialog(context);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '  spam  ');
    await tester.pump();
    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();

    expect(captured, 'spam');
  });

  testWidgets('returns null when cancelled', (tester) async {
    String? captured = 'unchanged';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  captured = await showReportContentDialog(context);
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(captured, isNull);
  });
}
