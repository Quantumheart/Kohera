import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/chat/widgets/message_list_view.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/mockito.dart';

import 'call_event_tile_test.mocks.dart';

MockEvent _event(String id, String type, DateTime ts) {
  final e = MockEvent();
  when(e.eventId).thenReturn(id);
  when(e.type).thenReturn(type);
  when(e.originServerTs).thenReturn(ts);
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

    // Supplied in a deliberately scrambled order, as the SDK's internal
    // sortOrder can diverge from originServerTs for call signaling events.
    final visible = MessageListViewState.buildVisibleEvents(
      [msgLate, callInvite, callHangup, msgEarly],
    );

    expect(_ids(visible), [r'$m2', r'$c2', r'$c1', r'$m1']);
  });

  test('deduplicates by eventId when merging extra events', () {
    final a = _event(r'$a', EventTypes.Message, DateTime(2026, 1, 15, 10));
    final aDup = _event(r'$a', EventTypes.Message, DateTime(2026, 1, 15, 10));
    final b = _event(r'$b', EventTypes.Message, DateTime(2026, 1, 15, 11));

    final visible = MessageListViewState.buildVisibleEvents(
      [a],
      extraEvents: [aDup, b],
    );

    expect(_ids(visible), [r'$b', r'$a']);
  });
}
