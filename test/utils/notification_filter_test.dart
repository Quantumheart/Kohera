import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/preferences_service.dart';
import 'package:kohera/core/utils/notification_filter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late PreferencesService prefs;

  const ownUserId = '@me:example.com';

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sp = await SharedPreferences.getInstance();
    prefs = PreferencesService(prefs: sp);
  });

  // ── effectiveUnreadCount ─────────────────────────────────────

  group('effectiveUnreadCount', () {
    test('returns notificationCount when level is all', () {
      expect(
        effectiveUnreadCount(
          notificationCount: 5,
          highlightCount: 0,
          lastEventBody: null,
          prefs: prefs,
        ),
        5,
      );
    });

    test('returns 0 when level is off', () async {
      await prefs.setNotificationLevel(NotificationLevel.off);
      expect(
        effectiveUnreadCount(
          notificationCount: 5,
          highlightCount: 0,
          lastEventBody: null,
          prefs: prefs,
        ),
        0,
      );
    });

    test('returns highlightCount when mentionsOnly with highlights', () async {
      await prefs.setNotificationLevel(NotificationLevel.mentionsOnly);
      expect(
        effectiveUnreadCount(
          notificationCount: 5,
          highlightCount: 3,
          lastEventBody: null,
          prefs: prefs,
        ),
        3,
      );
    });

    test('returns 1 when mentionsOnly with keyword match', () async {
      await prefs.setNotificationLevel(NotificationLevel.mentionsOnly);
      await prefs.addNotificationKeyword('hello');
      expect(
        effectiveUnreadCount(
          notificationCount: 5,
          highlightCount: 0,
          lastEventBody: 'say hello everyone',
          prefs: prefs,
        ),
        1,
      );
    });

    test('returns 0 when mentionsOnly with no match', () async {
      await prefs.setNotificationLevel(NotificationLevel.mentionsOnly);
      expect(
        effectiveUnreadCount(
          notificationCount: 5,
          highlightCount: 0,
          lastEventBody: 'nothing relevant',
          prefs: prefs,
        ),
        0,
      );
    });

    test('returns 0 when mentionsOnly with null lastEvent', () async {
      await prefs.setNotificationLevel(NotificationLevel.mentionsOnly);
      expect(
        effectiveUnreadCount(
          notificationCount: 5,
          highlightCount: 0,
          lastEventBody: null,
          prefs: prefs,
        ),
        0,
      );
    });
  });

  // ── shouldNotifyForEvent ─────────────────────────────────────

  group('shouldNotifyForEvent', () {
    test('returns false for own messages', () {
      expect(
        shouldNotifyForEvent(
          eventBody: 'hello',
          senderId: '@me:example.com',
          ownUserId: '@me:example.com',
          ownLowerDisplayName: 'me',
          prefs: prefs,
        ),
        isFalse,
      );
    });

    test('returns true for all level', () {
      expect(
        shouldNotifyForEvent(
          eventBody: 'hello',
          senderId: '@other:example.com',
          ownUserId: '@me:example.com',
          ownLowerDisplayName: 'me',
          prefs: prefs,
        ),
        isTrue,
      );
    });

    test('returns false for off level', () async {
      await prefs.setNotificationLevel(NotificationLevel.off);
      expect(
        shouldNotifyForEvent(
          eventBody: 'hello',
          senderId: '@other:example.com',
          ownUserId: '@me:example.com',
          ownLowerDisplayName: 'me',
          prefs: prefs,
        ),
        isFalse,
      );
    });

    test('mentionsOnly returns true when body contains user ID', () async {
      await prefs.setNotificationLevel(NotificationLevel.mentionsOnly);
      expect(
        shouldNotifyForEvent(
          eventBody: 'hey @me:example.com check this',
          senderId: '@other:example.com',
          ownUserId: ownUserId,
          ownLowerDisplayName: 'me',
          prefs: prefs,
        ),
        isTrue,
      );
    });

    test('mentionsOnly returns true when body contains display name',
        () async {
      await prefs.setNotificationLevel(NotificationLevel.mentionsOnly);
      expect(
        shouldNotifyForEvent(
          eventBody: 'hey Me, are you there?',
          senderId: '@other:example.com',
          ownUserId: ownUserId,
          ownLowerDisplayName: 'me',
          prefs: prefs,
        ),
        isTrue,
      );
    });

    test('mentionsOnly returns true on keyword match', () async {
      await prefs.setNotificationLevel(NotificationLevel.mentionsOnly);
      await prefs.addNotificationKeyword('urgent');
      expect(
        shouldNotifyForEvent(
          eventBody: 'This is URGENT please respond',
          senderId: '@other:example.com',
          ownUserId: '@me:example.com',
          ownLowerDisplayName: 'me',
          prefs: prefs,
        ),
        isTrue,
      );
    });

    test('mentionsOnly returns false with no match', () async {
      await prefs.setNotificationLevel(NotificationLevel.mentionsOnly);
      expect(
        shouldNotifyForEvent(
          eventBody: 'just a normal message',
          senderId: '@other:example.com',
          ownUserId: '@me:example.com',
          ownLowerDisplayName: 'me',
          prefs: prefs,
        ),
        isFalse,
      );
    });

    test('mentionsOnly returns false with null display name', () async {
      await prefs.setNotificationLevel(NotificationLevel.mentionsOnly);
      expect(
        shouldNotifyForEvent(
          eventBody: 'just a normal message',
          senderId: '@other:example.com',
          ownUserId: ownUserId,
          ownLowerDisplayName: null,
          prefs: prefs,
        ),
        isFalse,
      );
    });
  });
}
