import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/chat/services/message_timeline_controller.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([MockSpec<Event>()])
import 'message_list_view_order_test.mocks.dart';

MockEvent _event(String id, String type, DateTime ts, {String sender = '@me:example.com'}) {
  final e = MockEvent();
  when(e.eventId).thenReturn(id);
  when(e.type).thenReturn(type);
  when(e.originServerTs).thenReturn(ts);
  when(e.senderId).thenReturn(sender);
  when(e.body).thenReturn('');
  return e;
}

List<String> _ids(List<Event> events) =>
    events.map((e) => e.eventId).toList();

void main() {
  test('orders call events and messages chronologically (newest first)', () {
    final msgEarly =
        _event(r'$m1', EventTypes.Message, DateTime(2026, 1, 15, 22, 8));
    final callInvite =
        _event(r'$c1', 'm.call.invite', DateTime(2026, 1, 15, 22, 9));
    final callHangup =
        _event(r'$c2', 'm.call.hangup', DateTime(2026, 1, 15, 22, 10));
    final msgLate =
        _event(r'$m2', EventTypes.Message, DateTime(2026, 1, 15, 22, 11));

    final visible = MessageTimelineController.buildVisibleEvents(
      [msgLate, callInvite, callHangup, msgEarly],
    );

    expect(_ids(visible), [r'$m2', r'$c2', r'$c1', r'$m1']);
  });

  test('deduplicates by eventId when merging extra events', () {
    final a = _event(r'$a', EventTypes.Message, DateTime(2026, 1, 15, 10));
    final aDup = _event(r'$a', EventTypes.Message, DateTime(2026, 1, 15, 10));
    final b = _event(r'$b', EventTypes.Message, DateTime(2026, 1, 15, 11));

    final visible = MessageTimelineController.buildVisibleEvents(
      [a],
      extraEvents: [aDup, b],
    );

    expect(_ids(visible), [r'$b', r'$a']);
  });

  test('poll start events are visible; response/end events are filtered out', () {
    final pollStart = _event(
      r'$p1',
      PollEventContent.startType,
      DateTime(2026, 1, 15, 12),
    );
    final pollResponse = _event(
      r'$r1',
      PollEventContent.responseType,
      DateTime(2026, 1, 15, 12, 5),
    );
    final pollEnd = _event(
      r'$e1',
      PollEventContent.endType,
      DateTime(2026, 1, 15, 12, 10),
    );

    final visible = MessageTimelineController.buildVisibleEvents(
      [pollStart, pollResponse, pollEnd],
    );

    expect(_ids(visible), [r'$p1']);
  });

  test('filters out events from ignored users', () {
    final mine = _event(
      r'$m1',
      EventTypes.Message,
      DateTime(2026, 1, 15, 10),
      sender: '@me:example.com',
    );
    final ignored = _event(
      r'$m2',
      EventTypes.Message,
      DateTime(2026, 1, 15, 11),
      sender: '@bad:example.com',
    );

    final visible = MessageTimelineController.buildVisibleEvents(
      [mine, ignored],
      ignoredUserIds: ['@bad:example.com'],
    );

    expect(_ids(visible), [r'$m1']);
  });
}
