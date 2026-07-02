import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/chat/widgets/thread_indicator_chip.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: ThemeData(splashFactory: InkRipple.splashFactory),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  group('ThreadIndicatorChip', () {
    testWidgets('renders count and View thread label', (tester) async {
      await tester.pumpWidget(
        _wrap(
          ThreadIndicatorChip(
            replyCount: 2,
            isMe: false,
            onTap: () {},
          ),
        ),
      );

      expect(find.text('2 replies'), findsOneWidget);
      expect(find.text('View thread'), findsOneWidget);
    });

    testWidgets('singular label for one reply', (tester) async {
      await tester.pumpWidget(
        _wrap(
          ThreadIndicatorChip(
            replyCount: 1,
            isMe: false,
            onTap: () {},
          ),
        ),
      );

      expect(find.text('1 reply'), findsOneWidget);
    });

    testWidgets('tap fires onTap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _wrap(
          ThreadIndicatorChip(
            replyCount: 1,
            isMe: false,
            onTap: () => taps++,
          ),
        ),
      );

      await tester.tap(find.byType(InkWell));
      expect(taps, 1);
    });
  });
}
