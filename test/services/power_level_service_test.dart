import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/rooms/services/power_level_service.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([MockSpec<Room>(), MockSpec<Client>(), MockSpec<Event>()])
import 'power_level_service_test.mocks.dart';

Map<String, Object?> _plContent({
  int usersDefault = 0,
  int eventsDefault = 0,
  int stateDefault = 50,
  int invite = 0,
  int kick = 50,
  int ban = 50,
  int redact = 50,
  Map<String, Object?>? users,
  Map<String, Object?>? events,
  Map<String, Object?>? notifications,
}) =>
    {
      'users_default': usersDefault,
      'events_default': eventsDefault,
      'state_default': stateDefault,
      'invite': invite,
      'kick': kick,
      'ban': ban,
      'redact': redact,
      if (users != null) 'users': users,
      if (events != null) 'events': events,
      if (notifications != null) 'notifications': notifications,
    };

void main() {
  late MockRoom room;
  late MockClient client;
  late MockEvent plEvent;

  setUp(() {
    room = MockRoom();
    client = MockClient();
    plEvent = MockEvent();

    when(room.client).thenReturn(client);
    when(room.id).thenReturn('!test:example.com');
    when(room.getState(EventTypes.RoomPowerLevels)).thenReturn(plEvent);
    when(plEvent.content).thenReturn(_plContent());
    when(
      client.setRoomStateWithKey(any, any, any, any),
    ).thenAnswer((_) async => r'$eventId');
  });

  group('PowerLevelPatch.isEmpty', () {
    test('is true when no fields set', () {
      expect(const PowerLevelPatch().isEmpty, isTrue);
    });

    test('is false when any scalar is set', () {
      expect(const PowerLevelPatch(kick: 50).isEmpty, isFalse);
    });

    test('is false when users map is non-empty', () {
      expect(
        const PowerLevelPatch(users: {'@alice:example.com': 100}).isEmpty,
        isFalse,
      );
    });

    test('is true when maps are present but empty', () {
      expect(
        const PowerLevelPatch(users: {}, events: {}, notifications: {}).isEmpty,
        isTrue,
      );
    });
  });

  group('PowerLevelService.update', () {
    group('no-op patch', () {
      test('does not call setRoomStateWithKey when patch is empty', () async {
        await PowerLevelService.update(room, const PowerLevelPatch());

        verifyNever(client.setRoomStateWithKey(any, any, any, any));
      });
    });

    group('single-field update', () {
      test('merges kick threshold and preserves other fields', () async {
        await PowerLevelService.update(
          room,
          const PowerLevelPatch(kick: 75),
        );

        final captured = verify(
          client.setRoomStateWithKey(
            '!test:example.com',
            EventTypes.RoomPowerLevels,
            '',
            captureAny,
          ),
        ).captured.single as Map<String, Object?>;

        expect(captured['kick'], 75);
        expect(captured['ban'], 50);
        expect(captured['redact'], 50);
        expect(captured['state_default'], 50);
        expect(captured['users_default'], 0);
      });

      test('merges users_default', () async {
        await PowerLevelService.update(
          room,
          const PowerLevelPatch(usersDefault: 10),
        );

        final captured = verify(
          client.setRoomStateWithKey(any, any, any, captureAny),
        ).captured.single as Map<String, Object?>;

        expect(captured['users_default'], 10);
        expect(captured['kick'], 50);
      });

      test('merges invite threshold', () async {
        await PowerLevelService.update(
          room,
          const PowerLevelPatch(invite: 50),
        );

        final captured = verify(
          client.setRoomStateWithKey(any, any, any, captureAny),
        ).captured.single as Map<String, Object?>;

        expect(captured['invite'], 50);
      });
    });

    group('nested events map update', () {
      test('merges new event type without removing existing entries', () async {
        when(plEvent.content).thenReturn(
          _plContent(events: {EventTypes.RoomName: 50}),
        );

        await PowerLevelService.update(
          room,
          const PowerLevelPatch(events: {EventTypes.RoomTopic: 75}),
        );

        final captured = verify(
          client.setRoomStateWithKey(any, any, any, captureAny),
        ).captured.single as Map<String, Object?>;

        final events = (captured['events'] as Map<String, Object?>?)!;
        expect(events[EventTypes.RoomName], 50);
        expect(events[EventTypes.RoomTopic], 75);
      });

      test('overwrites an existing event entry', () async {
        when(plEvent.content).thenReturn(
          _plContent(
            events: {EventTypes.RoomName: 50, EventTypes.RoomTopic: 50},
          ),
        );

        await PowerLevelService.update(
          room,
          const PowerLevelPatch(events: {EventTypes.RoomName: 100}),
        );

        final captured = verify(
          client.setRoomStateWithKey(any, any, any, captureAny),
        ).captured.single as Map<String, Object?>;

        final events = (captured['events'] as Map<String, Object?>?)!;
        expect(events[EventTypes.RoomName], 100);
        expect(events[EventTypes.RoomTopic], 50);
      });

      test('creates events map when none exists', () async {
        when(plEvent.content).thenReturn(_plContent());

        await PowerLevelService.update(
          room,
          const PowerLevelPatch(events: {EventTypes.Encryption: 100}),
        );

        final captured = verify(
          client.setRoomStateWithKey(any, any, any, captureAny),
        ).captured.single as Map<String, Object?>;

        final events = (captured['events'] as Map<String, Object?>?)!;
        expect(events[EventTypes.Encryption], 100);
      });
    });

    group('users map update', () {
      test('merges per-user power level', () async {
        await PowerLevelService.update(
          room,
          const PowerLevelPatch(users: {'@alice:example.com': 50}),
        );

        final captured = verify(
          client.setRoomStateWithKey(any, any, any, captureAny),
        ).captured.single as Map<String, Object?>;

        final users = (captured['users'] as Map<String, Object?>?)!;
        expect(users['@alice:example.com'], 50);
      });

      test('preserves existing user entries', () async {
        when(plEvent.content).thenReturn(
          _plContent(users: {'@bob:example.com': 100}),
        );

        await PowerLevelService.update(
          room,
          const PowerLevelPatch(users: {'@alice:example.com': 50}),
        );

        final captured = verify(
          client.setRoomStateWithKey(any, any, any, captureAny),
        ).captured.single as Map<String, Object?>;

        final users = (captured['users'] as Map<String, Object?>?)!;
        expect(users['@bob:example.com'], 100);
        expect(users['@alice:example.com'], 50);
      });
    });

    group('notifications map update', () {
      test('merges notification key', () async {
        await PowerLevelService.update(
          room,
          const PowerLevelPatch(notifications: {'room': 50}),
        );

        final captured = verify(
          client.setRoomStateWithKey(any, any, any, captureAny),
        ).captured.single as Map<String, Object?>;

        final notifs = (captured['notifications'] as Map<String, Object?>?)!;
        expect(notifs['room'], 50);
      });
    });

    group('missing power_levels state event', () {
      test('uses empty base when no power_levels event exists', () async {
        when(room.getState(EventTypes.RoomPowerLevels)).thenReturn(null);

        await PowerLevelService.update(
          room,
          const PowerLevelPatch(kick: 50),
        );

        final captured = verify(
          client.setRoomStateWithKey(any, any, any, captureAny),
        ).captured.single as Map<String, Object?>;

        expect(captured['kick'], 50);
      });
    });

    group('forbidden response', () {
      test('wraps MatrixException in PowerLevelException', () async {
        when(
          client.setRoomStateWithKey(any, any, any, any),
        ).thenThrow(
          MatrixException.fromJson({
            'errcode': 'M_FORBIDDEN',
            'error': 'You do not have permission',
          }),
        );

        expect(
          () => PowerLevelService.update(
            room,
            const PowerLevelPatch(kick: 75),
          ),
          throwsA(
            isA<PowerLevelException>()
                .having((e) => e.errcode, 'errcode', 'M_FORBIDDEN')
                .having(
                  (e) => e.message,
                  'message',
                  contains('permission'),
                ),
          ),
        );
      });
    });
  });
}
