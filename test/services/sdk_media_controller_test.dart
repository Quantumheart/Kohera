import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/chat/services/sdk_media_controller.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([
  MockSpec<Event>(),
  MockSpec<Room>(),
  MockSpec<Client>(),
])
import 'sdk_media_controller_test.mocks.dart';

void main() {
  late MockEvent event;
  late MockRoom room;
  late MockClient client;

  setUp(() {
    event = MockEvent();
    room = MockRoom();
    client = MockClient();

    when(event.eventId).thenReturn(r'$123:server');
    when(event.room).thenReturn(room);
    when(room.client).thenReturn(client);
    when(client.homeserver).thenReturn(Uri.parse('https://example.com'));
    when(client.accessToken).thenReturn('token123');
  });

  group('SdkMediaController', () {
    test('isEncrypted delegates to event', () {
      when(event.isAttachmentEncrypted).thenReturn(true);
      final controller = SdkMediaController(event);
      expect(controller.isEncrypted, isTrue);
    });

    test('eventId delegates to event', () {
      final controller = SdkMediaController(event);
      expect(controller.eventId, r'$123:server');
    });

    test('isPendingSend returns true for sending status', () {
      when(event.status).thenReturn(EventStatus.sending);
      final controller = SdkMediaController(event);
      expect(controller.isPendingSend, isTrue);
    });

    test('isPendingSend returns true for error status', () {
      when(event.status).thenReturn(EventStatus.error);
      final controller = SdkMediaController(event);
      expect(controller.isPendingSend, isTrue);
    });

    test('isPendingSend returns false for synced status', () {
      when(event.status).thenReturn(EventStatus.synced);
      final controller = SdkMediaController(event);
      expect(controller.isPendingSend, isFalse);
    });

    test('mimeType extracts from content info', () {
      when(event.content).thenReturn(<String, Object?>{
        'info': {'mimetype': 'image/png'},
      });
      final controller = SdkMediaController(event);
      expect(controller.mimeType, 'image/png');
    });

    test('mimeType returns null when info missing', () {
      when(event.content).thenReturn(<String, Object?>{});
      final controller = SdkMediaController(event);
      expect(controller.mimeType, isNull);
    });

    test('downloadAndDecrypt returns bytes', () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final file = MatrixFile(bytes: bytes, name: 'test.png');
      when(event.downloadAndDecryptAttachment()).thenAnswer((_) async => file);

      final controller = SdkMediaController(event);
      final result = await controller.downloadAndDecrypt();
      expect(result, bytes);
    });

    test('downloadAndDecrypt with getThumbnail', () async {
      final bytes = Uint8List.fromList([4, 5, 6]);
      final file = MatrixFile(bytes: bytes, name: 'thumb.png');
      when(event.downloadAndDecryptAttachment(getThumbnail: true))
          .thenAnswer((_) async => file);

      final controller = SdkMediaController(event);
      final result = await controller.downloadAndDecrypt(getThumbnail: true);
      expect(result, bytes);
    });

    test('getAttachmentUri returns URL string', () async {
      when(
        event.getAttachmentUri(
          getThumbnail: anyNamed('getThumbnail'),
          width: anyNamed('width'),
          height: anyNamed('height'),
        ),
      ).thenAnswer((_) async => Uri.parse('https://example.com/media'));

      final controller = SdkMediaController(event);
      final result = await controller.getAttachmentUri(width: 280, height: 260);
      expect(result, 'https://example.com/media');
    });

    test('getAttachmentUri returns null when SDK returns null', () async {
      when(
        event.getAttachmentUri(
          getThumbnail: anyNamed('getThumbnail'),
          width: anyNamed('width'),
          height: anyNamed('height'),
        ),
      ).thenAnswer((_) async => null);
      when(event.attachmentMxcUrl).thenReturn(null);

      final controller = SdkMediaController(event);
      final result = await controller.getAttachmentUri(getThumbnail: true);
      expect(result, isNull);
    });

    test('authHeaders returns headers for same-host URL', () {
      final controller = SdkMediaController(event);
      final headers = controller.authHeaders('https://example.com/media');
      expect(headers, isNotNull);
      expect(headers!['authorization'], 'Bearer token123');
    });

    test('authHeaders returns null for federated URL', () {
      final controller = SdkMediaController(event);
      final headers = controller.authHeaders('https://other.com/media');
      expect(headers, isNull);
    });
  });
}
