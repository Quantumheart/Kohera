import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/chat/widgets/thread_indicator_chip.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([MockSpec<Event>(), MockSpec<Timeline>()])
import 'thread_indicator_chip_test.mocks.dart';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: Center(child: child)));

void main() {
  group('ThreadIndicatorChip', () {
    late MockEvent root;
    late MockTimeline timeline;

    setUp(() {
      root = MockEvent();
      timeline = MockTimeline();
    });

    testWidgets('renders count and View thread label', (tester) async {
      final child1 = MockEvent();
      final child2 = MockEvent();
      when(root.aggregatedEvents(timeline, RelationshipTypes.thread))
          .thenReturn({child1, child2});

      await tester.pumpWidget(_wrap(
        ThreadIndicatorChip(
          event: root,
          timeline: timeline,
          isMe: false,
          onTap: () {},
        ),
      ),);

      expect(find.text('2 replies'), findsOneWidget);
      expect(find.text('View thread'), findsOneWidget);
    });

    testWidgets('singular label for one reply', (tester) async {
      when(root.aggregatedEvents(timeline, RelationshipTypes.thread))
          .thenReturn({MockEvent()});

      await tester.pumpWidget(_wrap(
        ThreadIndicatorChip(
          event: root,
          timeline: timeline,
          isMe: false,
          onTap: () {},
        ),
      ),);

      expect(find.text('1 reply'), findsOneWidget);
    });

    testWidgets('renders nothing when no thread children', (tester) async {
      when(root.aggregatedEvents(timeline, RelationshipTypes.thread))
          .thenReturn(<Event>{});

      await tester.pumpWidget(_wrap(
        ThreadIndicatorChip(
          event: root,
          timeline: timeline,
          isMe: false,
          onTap: () {},
        ),
      ),);

      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('tap fires onTap', (tester) async {
      var taps = 0;
      when(root.aggregatedEvents(timeline, RelationshipTypes.thread))
          .thenReturn({MockEvent()});

      await tester.pumpWidget(_wrap(
        ThreadIndicatorChip(
          event: root,
          timeline: timeline,
          isMe: false,
          onTap: () => taps++,
        ),
      ),);

      await tester.tap(find.byType(InkWell));
      expect(taps, 1);
    });
  });
}
