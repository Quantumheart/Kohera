import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/features/chat/widgets/typing_indicator.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _wrap(
  List<String> typingNames, {
  PreferencesService? prefs,
}) {
  return ChangeNotifierProvider<PreferencesService>.value(
    value: prefs ?? PreferencesService(),
    child: MaterialApp(
      theme: ThemeData(splashFactory: InkRipple.splashFactory),
      home: Scaffold(
        body: TypingIndicator(
          typingDisplayNamesProvider: () => typingNames,
          syncStream: const Stream.empty(),
        ),
      ),
    ),
  );
}

void main() {
  group('TypingIndicator', () {
    testWidgets('empty typing names renders nothing', (tester) async {
      await tester.pumpWidget(_wrap([]));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(TypingIndicator), findsOneWidget);
      expect(find.textContaining('typing'), findsNothing);
    });

    testWidgets('single typer shows "X is typing"', (tester) async {
      await tester.pumpWidget(_wrap(['Alice']));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Alice is typing'), findsOneWidget);
    });

    testWidgets('two typers shows "X and Y are typing"', (tester) async {
      await tester.pumpWidget(_wrap(['Alice', 'Bob']));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Alice and Bob are typing'), findsOneWidget);
    });

    testWidgets('three typers shows all names', (tester) async {
      await tester.pumpWidget(_wrap(['Alice', 'Bob', 'Charlie']));
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.text('Alice, Bob, and Charlie are typing'),
        findsOneWidget,
      );
    });

    testWidgets('four+ typers shows "+N others"', (tester) async {
      await tester.pumpWidget(_wrap(['Alice', 'Bob', 'Charlie', 'Dave']));
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.text('Alice, Bob, and 2 others are typing'),
        findsOneWidget,
      );
    });

    testWidgets('hidden when typing indicators disabled', (tester) async {
      SharedPreferences.setMockInitialValues({'typing_indicators': false});
      final sp = await SharedPreferences.getInstance();
      final prefs = PreferencesService(prefs: sp);

      await tester.pumpWidget(_wrap(['Alice'], prefs: prefs));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Alice is typing'), findsNothing);
    });
  });

  group('TypingIndicator.formatTypers', () {
    test('single name', () {
      expect(TypingIndicator.formatTypers(['Alice']), 'Alice is typing');
    });

    test('two names', () {
      expect(
        TypingIndicator.formatTypers(['Alice', 'Bob']),
        'Alice and Bob are typing',
      );
    });

    test('three names', () {
      expect(
        TypingIndicator.formatTypers(['Alice', 'Bob', 'Charlie']),
        'Alice, Bob, and Charlie are typing',
      );
    });

    test('four names', () {
      expect(
        TypingIndicator.formatTypers(['Alice', 'Bob', 'Charlie', 'Dave']),
        'Alice, Bob, and 2 others are typing',
      );
    });
  });
}
