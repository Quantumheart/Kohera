import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/chat/models/kohera_message_display.dart';
import 'package:kohera/features/chat/models/kohera_message_status.dart';

void main() {
  group('KoheraMessageDisplay', () {
    test('constructs with all fields', () {
      final message = KoheraMessageDisplay(
        eventId: r'$1:server',
        senderId: '@alice:server',
        senderName: 'Alice',
        body: 'hello',
        messageType: 'm.text',
        eventType: 'm.room.message',
        timestamp: DateTime(2026),
        status: KoheraMessageStatus.sent,
        content: const <String, Object?>{},
      );

      expect(message.eventId, r'$1:server');
      expect(message.senderId, '@alice:server');
      expect(message.senderName, 'Alice');
      expect(message.body, 'hello');
      expect(message.messageType, 'm.text');
      expect(message.eventType, 'm.room.message');
      expect(message.isRedacted, false);
      expect(message.status, KoheraMessageStatus.sent);
      expect(message.isEdited, false);
    });

    test('equality based on eventId', () {
      final a = KoheraMessageDisplay(
        eventId: r'$1:s',
        senderId: '@a:s',
        senderName: 'A',
        body: 'x',
        messageType: 'm.text',
        eventType: 'm.room.message',
        timestamp: DateTime.now(),
        status: KoheraMessageStatus.sent,
        content: const <String, Object?>{},
      );
      final b = KoheraMessageDisplay(
        eventId: r'$1:s',
        senderId: '@b:s',
        senderName: 'B',
        body: 'y',
        messageType: 'm.emote',
        eventType: 'm.call.invite',
        timestamp: DateTime.now().add(const Duration(hours: 1)),
        isRedacted: true,
        status: KoheraMessageStatus.error,
        isEdited: true,
        content: const {'key': 'val'},
      );

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('inequality for different eventIds', () {
      final a = KoheraMessageDisplay(
        eventId: r'$1:s',
        senderId: '@a:s',
        senderName: 'A',
        body: '',
        messageType: 'm.text',
        eventType: 'm.room.message',
        timestamp: DateTime.now(),
        status: KoheraMessageStatus.sent,
        content: const <String, Object?>{},
      );
      final b = KoheraMessageDisplay(
        eventId: r'$2:s',
        senderId: '@a:s',
        senderName: 'A',
        body: '',
        messageType: 'm.text',
        eventType: 'm.room.message',
        timestamp: DateTime.now(),
        status: KoheraMessageStatus.sent,
        content: const <String, Object?>{},
      );

      expect(a, isNot(equals(b)));
    });

    test('copyWith updates fields', () {
      final original = KoheraMessageDisplay(
        eventId: r'$1:s',
        senderId: '@a:s',
        senderName: 'A',
        body: 'hello',
        messageType: 'm.text',
        eventType: 'm.room.message',
        timestamp: DateTime(2026),
        status: KoheraMessageStatus.sending,
        content: const <String, Object?>{},
      );

      final updated = original.copyWith(
        body: 'edited',
        status: KoheraMessageStatus.sent,
        isEdited: true,
      );

      expect(updated.eventId, r'$1:s');
      expect(updated.body, 'edited');
      expect(updated.status, KoheraMessageStatus.sent);
      expect(updated.isEdited, true);
      expect(updated.senderName, 'A');
    });
  });
}
