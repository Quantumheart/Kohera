import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/data/models/kohera_event_types.dart';
import 'package:kohera/data/models/kohera_timeline_event.dart';
import 'package:kohera/features/chat/services/message_timeline_controller.dart';

KoheraTimelineEvent _event(
  String id,
  String type,
  DateTime ts, {
  String sender = '@me:example.com',
}) {
  return KoheraTimelineEvent(
    eventId: id,
    senderId: sender,
    type: type,
    body: '',
    originServerTs: ts,
    redacted: false,
    canRedact: false,
    content: const {},
  );
}

List<String> _ids(List<KoheraTimelineEvent> events) =>
    events.map((e) => e.eventId).toList();

void main() {
  test('orders call events and messages chronologically (newest first)', () {
    final msgEarly =
        _event(r'$m1', KoheraEventTypes.message, DateTime(2026, 1, 15, 22, 8));
    final callInvite =
        _event(r'$c1', 'm.call.invite', DateTime(2026, 1, 15, 22, 9));
    final callHangup =
        _event(r'$c2', 'm.call.hangup', DateTime(2026, 1, 15, 22, 10));
    final msgLate =
        _event(r'$m2', KoheraEventTypes.message, DateTime(2026, 1, 15, 22, 11));

    final visible = MessageTimelineController.buildVisibleEvents(
      [msgLate, callInvite, callHangup, msgEarly],
    );

    expect(_ids(visible), [r'$m2', r'$c2', r'$c1', r'$m1']);
  });

  test('deduplicates by eventId when merging extra events', () {
    final a = _event(r'$a', KoheraEventTypes.message, DateTime(2026, 1, 15, 10));
    final aDup =
        _event(r'$a', KoheraEventTypes.message, DateTime(2026, 1, 15, 10));
    final b = _event(r'$b', KoheraEventTypes.message, DateTime(2026, 1, 15, 11));

    final visible = MessageTimelineController.buildVisibleEvents(
      [a],
      extraEvents: [aDup, b],
    );

    expect(_ids(visible), [r'$b', r'$a']);
  });

  test('poll start events are visible; response/end events are filtered out',
      () {
    final pollStart = _event(
      r'$p1',
      KoheraEventTypes.pollStart,
      DateTime(2026, 1, 15, 12),
    );
    final pollResponse = _event(
      r'$r1',
      'org.matrix.msc3381.poll.response',
      DateTime(2026, 1, 15, 12, 5),
    );
    final pollEnd = _event(
      r'$e1',
      'org.matrix.msc3381.poll.end',
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
      KoheraEventTypes.message,
      DateTime(2026, 1, 15, 10),
    );
    final ignored = _event(
      r'$m2',
      KoheraEventTypes.message,
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
