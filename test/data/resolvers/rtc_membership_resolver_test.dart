import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/data/models/kohera_call_member_state.dart';
import 'package:kohera/data/resolvers/rtc_membership_resolver.dart';

void main() {
  final nowMs = DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> membership({int expires = 14400000}) => {
        'application': 'm.call',
        'call_id': '',
        'scope': 'm.room',
        'device_id': 'DEV',
        'expires': expires,
        'focus_active': {'type': 'livekit'},
        'foci_preferred': [
          {
            'type': 'livekit',
            'livekit_service_url': 'https://lk.example.com',
            'livekit_alias': 'alias',
          },
        ],
      };

  KoheraCallMemberState state(
    String key,
    String sender, {
    Map<String, dynamic>? content,
    int? originTs,
  }) =>
      KoheraCallMemberState(
        stateKey: key,
        senderId: sender,
        content: content ?? membership(),
        originTsMs: originTs ?? nowMs,
      );

  group('isMembershipActive', () {
    test('expires_ts in the future is active', () {
      expect(
        RtcMembershipResolver.isMembershipActive(
          {'expires_ts': nowMs + 1000},
          nowMs,
          nowMs,
        ),
        isTrue,
      );
    });

    test('expires_ts in the past is inactive', () {
      expect(
        RtcMembershipResolver.isMembershipActive(
          {'expires_ts': nowMs - 1000},
          nowMs,
          nowMs,
        ),
        isFalse,
      );
    });

    test('relative expires uses origin timestamp', () {
      expect(
        RtcMembershipResolver.isMembershipActive(
          {'expires': 5000},
          nowMs - 10000,
          nowMs,
        ),
        isFalse,
      );
      expect(
        RtcMembershipResolver.isMembershipActive(
          {'expires': 60000},
          nowMs - 10000,
          nowMs,
        ),
        isTrue,
      );
    });

    test('missing expiry fields is inactive', () {
      expect(
        RtcMembershipResolver.isMembershipActive({}, nowMs, nowMs),
        isFalse,
      );
    });
  });

  group('userIdFromStateKey', () {
    test('extracts the user id', () {
      expect(
        RtcMembershipResolver.userIdFromStateKey('_@alice:example.com_DEV_m.call'),
        '@alice:example.com',
      );
    });

    test('returns null for malformed keys', () {
      expect(RtcMembershipResolver.userIdFromStateKey('no-match'), isNull);
    });
  });

  group('activeMemberships', () {
    test('skips empty content', () {
      expect(
        RtcMembershipResolver.activeMemberships([
          state('_@a:s_D_m.call', '@a:s', content: {}),
        ]),
        isEmpty,
      );
    });

    test('flattens the memberships list shape', () {
      expect(
        RtcMembershipResolver.activeMemberships([
          state('_@a:s_D_m.call', '@a:s', content: {
            'memberships': [membership()],
          }),
        ]),
        hasLength(1),
      );
    });

    test('includes the legacy single-membership shape', () {
      expect(
        RtcMembershipResolver.activeMemberships([
          state('_@a:s_D_m.call', '@a:s'),
        ]),
        hasLength(1),
      );
    });
  });

  group('hasRemoteActiveCall', () {
    test('ignores local memberships', () {
      final states = [
        state('_@alice:s_D_m.call', '@alice:s'),
        state('_@bob:s_D_m.call', '@bob:s'),
      ];
      expect(
        RtcMembershipResolver.hasRemoteActiveCall(states, '@alice:s'),
        isTrue,
      );
      expect(
        RtcMembershipResolver.hasRemoteActiveCall(
          [states[0]],
          '@alice:s',
        ),
        isFalse,
      );
    });
  });

  group('activeParticipantUserIds', () {
    test('prefers the state key over the sender id', () {
      expect(
        RtcMembershipResolver.activeParticipantUserIds([
          state('_@alice:s_D_m.call', '@other:s'),
        ]),
        {'@alice:s'},
      );
    });

    test('falls back to the sender id', () {
      expect(
        RtcMembershipResolver.activeParticipantUserIds([
          state('opaque', '@sender:s'),
        ]),
        {'@sender:s'},
      );
    });
  });

  group('activeCallIds and participantCount', () {
    test('collects call ids and counts per group call', () {
      final states = [
        state('_@a:s_D_m.call', '@a:s',
            content: {...membership(), 'call_id': 'g1'}),
        state('_@b:s_D_m.call', '@b:s',
            content: {...membership(), 'call_id': 'g1'}),
      ];
      expect(RtcMembershipResolver.activeCallIds(states), ['g1']);
      expect(RtcMembershipResolver.participantCount(states, 'g1'), 2);
      expect(RtcMembershipResolver.participantCount(states, 'g2'), 0);
    });
  });

  group('selectOldestFocus', () {
    test('selects the membership with the oldest created_ts', () {
      final states = [
        state('_@a:s_D_m.call', '@a:s', content: {
          ...membership(),
          'created_ts': 200,
          'foci_preferred': [
            {'type': 'livekit', 'livekit_service_url': 'https://new.example.com'},
          ],
        }, originTs: nowMs),
        state('_@b:s_D_m.call', '@b:s', content: {
          ...membership(),
          'created_ts': 100,
        }, originTs: nowMs),
      ];
      final focus = RtcMembershipResolver.selectOldestFocus(states);
      expect(focus?.url, 'https://lk.example.com');
      expect(focus?.alias, 'alias');
    });

    test('excludes memberships of the given user', () {
      final states = [
        state('_@alice:s_D_m.call', '@alice:s'),
        state('_@bob:s_D_m.call', '@bob:s'),
      ];
      final focus = RtcMembershipResolver.selectOldestFocus(
        states,
        excludeUserId: '@alice:s',
      );
      expect(focus?.url, 'https://lk.example.com');
    });

    test('returns null when no focus is present', () {
      expect(
        RtcMembershipResolver.selectOldestFocus([
          state('_@a:s_D_m.call', '@a:s', content: {
            ...membership(),
            'foci_preferred': <dynamic>[],
          }),
        ]),
        isNull,
      );
    });
  });
}
