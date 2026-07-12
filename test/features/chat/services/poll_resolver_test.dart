import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/chat/models/kohera_poll.dart';
import 'package:kohera/features/chat/services/poll_resolver.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([
  MockSpec<Event>(),
  MockSpec<Room>(),
  MockSpec<Timeline>(),
])
import 'poll_resolver_test.mocks.dart';

const _startType = PollEventContent.startType;

Map<String, Object?> _pollContent({
  required String question,
  required List<({String id, String label})> answers,
  PollKind kind = PollKind.undisclosed,
  int maxSelections = 1,
}) {
  return {
    PollEventContent.mTextJsonKey: question,
    _startType: {
      if (kind != null) 'kind': kind.name,
      'max_selections': maxSelections,
      'question': {
        PollEventContent.mTextJsonKey: question,
        'body': question,
      },
      'answers': [
        for (final a in answers)
          {
            'id': a.id,
            PollEventContent.mTextJsonKey: a.label,
          },
      ],
    },
  };
}

MockEvent _startEvent({
  required String eventId,
  required Map<String, Object?> content,
  String senderId = '@creator:example.com',
}) {
  final event = MockEvent();
  when(event.type).thenReturn(_startType);
  when(event.eventId).thenReturn(eventId);
  when(event.senderId).thenReturn(senderId);
  when(event.originServerTs).thenReturn(DateTime(2026, 1, 15, 12));
  when(event.content).thenReturn(content);
  return event;
}

MockTimeline _emptyTimeline(String eventId) {
  final timeline = MockTimeline();
  when(timeline.aggregatedEvents).thenReturn({});
  return timeline;
}

void main() {
  group('PollResolver', () {
    final answers = <(String, String)>[
      ('a1', 'Yes'),
      ('a2', 'No'),
    ].map((a) => (id: a.$1, label: a.$2)).toList();

    test('disclosed open poll shows tally with zeroed counts', () {
      final event = _startEvent(
        eventId: r'$p1',
        content: _pollContent(
          question: 'Tea or coffee?',
          answers: answers,
          kind: PollKind.disclosed,
        ),
      );
      final timeline = _emptyTimeline(r'$p1');

      final poll = const PollResolver()(event, timeline);

      expect(poll.kind, KoheraPollKind.disclosed);
      expect(poll.ended, isFalse);
      expect(poll.showsTally, isTrue);
      expect(poll.answers.map((a) => a.label), ['Yes', 'No']);
      expect(poll.tallies, {'a1': 0, 'a2': 0});
      expect(poll.responseCount, 0);
    });

    test('undisclosed open poll hides tally', () {
      final event = _startEvent(
        eventId: r'$p2',
        content: _pollContent(
          question: 'Secret?',
          answers: answers,
          kind: PollKind.undisclosed,
        ),
      );
      final timeline = _emptyTimeline(r'$p2');

      final poll = const PollResolver()(event, timeline);

      expect(poll.kind, KoheraPollKind.undisclosed);
      expect(poll.ended, isFalse);
      expect(poll.showsTally, isFalse);
      expect(poll.tallies, {'a1': 0, 'a2': 0});
      expect(poll.responseCount, 0);
    });
  });
}