import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/rooms/models/kohera_export_format.dart';
import 'package:kohera/features/rooms/models/kohera_room_export.dart';
import 'package:kohera/features/rooms/services/history_export_formatters.dart';

KoheraExportedMessage _msg({
  String eventId = r'$ev1:example.com',
  String sender = '@alice:example.com',
  String senderName = 'Alice',
  DateTime? ts,
  String messageType = 'm.text',
  String body = 'Hello',
  String? formatted,
  String? mediaUrl,
  String? mediaFileName,
  String? mediaMimetype,
}) =>
    KoheraExportedMessage(
      eventId: eventId,
      senderId: sender,
      senderDisplayname: senderName,
      timestamp: ts ?? DateTime.utc(2024, 1, 2, 3, 4, 5),
      messageType: messageType,
      body: body,
      formattedBody: formatted,
      mediaUrl: mediaUrl,
      mediaFileName: mediaFileName,
      mediaMimetype: mediaMimetype,
    );

KoheraRoomExport _export({
  KoheraExportFormat format = KoheraExportFormat.json,
  List<KoheraExportedMessage> messages = const [],
  bool includeMedia = false,
  DateTime? start,
  DateTime? end,
  String topic = 'A topic',
  String? canonicalAlias = '#room:example.com',
}) =>
    KoheraRoomExport(
      meta: KoheraExportRoomMeta(
        roomId: '!room:example.com',
        displayname: 'Test Room',
        canonicalAlias: canonicalAlias,
        topic: topic,
        exportedAt: DateTime.utc(2024, 1, 3),
      ),
      messages: messages,
      options: KoheraExportOptions(
        format: format,
        includeMedia: includeMedia,
        start: start,
        end: end,
      ),
    );

void main() {
  const formatters = HistoryExportFormatters();

  group('HistoryExportFormatters', () {
    test('json includes room meta and messages', () {
      final out = formatters.format(_export(
        messages: [_msg(body: 'Hello <world>', formatted: '<b>Hi</b>')],
      ));
      final decoded = jsonDecode(out) as Map<String, Object?>;
      expect(decoded['room'], isA<Map<String, Object?>>());
      expect((decoded['room']! as Map)['displayname'], 'Test Room');
      final messages = decoded['messages']! as List;
      expect(messages, hasLength(1));
      final m = messages.first! as Map<String, Object?>;
      expect(m['body'], 'Hello <world>');
      expect(m['formatted_body'], '<b>Hi</b>');
    });

    test('json escapes nothing in JSON encoding (handled by encoder)', () {
      final out = formatters.format(_export(
        messages: [_msg(body: 'a "quote" & <tag>')],
      ));
      final decoded = jsonDecode(out) as Map<String, Object?>;
      expect(
        ((decoded['messages']! as List).first! as Map<String, Object?>)['body'],
        'a "quote" & <tag>',
      );
    });

    test('json includes media entries when present', () {
      final out = formatters.format(_export(
        includeMedia: true,
        messages: [
          _msg(
            body: 'image.png',
            mediaUrl: 'mxc://example.com/abc',
            mediaFileName: 'image.png',
            mediaMimetype: 'image/png',
          ),
        ],
      ));
      final decoded = jsonDecode(out) as Map<String, Object?>;
      final m = (decoded['messages']! as List).first! as Map<String, Object?>;
      expect(m['media_url'], 'mxc://example.com/abc');
      expect(m['media_file_name'], 'image.png');
      expect(m['media_mimetype'], 'image/png');
    });

    test('json omits media entries when absent', () {
      final out = formatters.format(_export(
        messages: [_msg(body: 'plain')],
      ));
      final decoded = jsonDecode(out) as Map<String, Object?>;
      final m = (decoded['messages']! as List).first! as Map<String, Object?>;
      expect(m.containsKey('media_url'), isFalse);
    });

    test('html escapes user content', () {
      final out = formatters.format(_export(
        format: KoheraExportFormat.html,
        messages: [_msg(body: '<script>x</script>', senderName: 'A & B')],
      ));
      expect(out, contains('&lt;script&gt;'));
      expect(out, contains('A &amp; B'));
      expect(out, isNot(contains('<script>')));
    });

    test('html renders media as link', () {
      final out = formatters.format(_export(
        format: KoheraExportFormat.html,
        includeMedia: true,
        messages: [
          _msg(
            body: 'pic.png',
            mediaUrl: 'mxc://example.com/abc',
            mediaFileName: 'pic.png',
            mediaMimetype: 'image/png',
          ),
        ],
      ));
      expect(out, contains('href="mxc://example.com/abc"'));
      expect(out, contains('[media: pic.png (image/png)]'));
    });

    test('plaintext lists one line per message', () {
      final out = formatters.format(_export(
        format: KoheraExportFormat.plaintext,
        messages: [
          _msg(body: 'first'),
          _msg(eventId: r'$ev2:example.com', body: 'second', senderName: 'Bob'),
        ],
      ));
      expect(out, contains('# Test Room'));
      expect(out, contains('Alice: first'));
      expect(out, contains('Bob: second'));
    });

    test('plaintext media line includes url and mime', () {
      final out = formatters.format(_export(
        format: KoheraExportFormat.plaintext,
        includeMedia: true,
        messages: [
          _msg(
            body: 'pic.png',
            mediaUrl: 'mxc://example.com/abc',
            mediaFileName: 'pic.png',
            mediaMimetype: 'image/png',
          ),
        ],
      ));
      expect(out, contains('[media: pic.png] <mxc://example.com/abc> (image/png)'));
    });

    test('all formats handle empty message list', () {
      for (final f in KoheraExportFormat.values) {
        final out = formatters.format(_export(format: f));
        expect(out, isNotEmpty, reason: f.name);
      }
    });

    test('plaintext includes date range header when set', () {
      final out = formatters.format(_export(
        format: KoheraExportFormat.plaintext,
        start: DateTime.utc(2024),
        end: DateTime.utc(2024, 2),
      ));
      expect(out, contains('From: 2024-01-01T00:00:00.000Z'));
      expect(out, contains('Until: 2024-02-01T00:00:00.000Z'));
    });
  });
}
