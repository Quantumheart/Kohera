import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/rooms/models/kohera_export_format.dart';
import 'package:kohera/features/rooms/services/room_history_exporter.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<Room>(),
  MockSpec<Timeline>(),
  MockSpec<Event>(),
  MockSpec<User>(),
])
import '../../../mocks/matrix_service_mock.mocks.dart';
import 'room_history_exporter_test.mocks.dart';

MockEvent _msgEvent({
  required String eventId,
  required String senderId,
  required DateTime ts,
  String body = 'Hello',
  String formatted = '',
  String messageType = MessageTypes.Text,
  Map<String, Object?>? content,
}) {
  final event = MockEvent();
  when(event.type).thenReturn(EventTypes.Message);
  when(event.eventId).thenReturn(eventId);
  when(event.senderId).thenReturn(senderId);
  when(event.originServerTs).thenReturn(ts);
  when(event.messageType).thenReturn(messageType);
  when(event.content).thenReturn(content ?? {'body': body});
  when(event.body).thenReturn(body);
  when(event.text).thenReturn(body);
  when(event.formattedText).thenReturn(formatted);
  when(event.hasAttachment).thenReturn(false);
  when(event.redacted).thenReturn(false);
  return event;
}

MockEvent _mediaEvent({
  required String eventId,
  required String senderId,
  required DateTime ts,
  required String mxcUrl,
  required String fileName,
  required String mimetype,
}) {
  final event = MockEvent();
  when(event.type).thenReturn(EventTypes.Message);
  when(event.eventId).thenReturn(eventId);
  when(event.senderId).thenReturn(senderId);
  when(event.originServerTs).thenReturn(ts);
  when(event.messageType).thenReturn(MessageTypes.Image);
  when(event.content).thenReturn({
    'body': fileName,
    'url': mxcUrl,
    'msgtype': MessageTypes.Image,
    'info': {'mimetype': mimetype},
  });
  when(event.body).thenReturn(fileName);
  when(event.text).thenReturn(fileName);
  when(event.formattedText).thenReturn('');
  when(event.hasAttachment).thenReturn(true);
  when(event.attachmentMxcUrl).thenReturn(Uri.parse(mxcUrl));
  when(event.attachmentMimetype).thenReturn(mimetype);
  when(event.redacted).thenReturn(false);
  return event;
}

MockEvent _stateEvent({
  required String eventId,
  required DateTime ts,
}) {
  final event = MockEvent();
  when(event.type).thenReturn(EventTypes.RoomMember);
  when(event.eventId).thenReturn(eventId);
  when(event.senderId).thenReturn('@sys:example.com');
  when(event.originServerTs).thenReturn(ts);
  return event;
}

void main() {
  late MockClient mockClient;
  late MockMatrixService mockMatrix;
  late MockRoom mockRoom;
  late MockTimeline mockTimeline;

  setUp(() {
    mockClient = MockClient();
    mockMatrix = MockMatrixService();
    mockRoom = MockRoom();
    mockTimeline = MockTimeline();

    when(mockMatrix.client).thenReturn(mockClient);
    when(mockClient.getRoomById('!room:example.com')).thenReturn(mockRoom);
    when(mockRoom.id).thenReturn('!room:example.com');
    when(mockRoom.getLocalizedDisplayname()).thenReturn('Test Room');
    when(mockRoom.canonicalAlias).thenReturn('#room:example.com');
    when(mockRoom.topic).thenReturn('A topic');
    when(mockRoom.client).thenReturn(mockClient);
    when(mockRoom.getTimeline(
      eventContextId: anyNamed('eventContextId'),
      onUpdate: anyNamed('onUpdate'),
    )).thenAnswer((_) async => mockTimeline);
    when(mockTimeline.events).thenReturn([]);
    when(mockTimeline.canRequestHistory).thenReturn(false);
  });

  MockUser user(String id, String name) {
    final u = MockUser();
    when(u.id).thenReturn(id);
    when(u.calcDisplayname(i18n: anyNamed('i18n'))).thenReturn(name);
    when(mockRoom.unsafeGetUserFromMemoryOrFallback(id)).thenReturn(u);
    return u;
  }

  group('RoomHistoryExporter', () {
    test('converts chronological message events', () async {
      user('@alice:example.com', 'Alice');
      user('@bob:example.com', 'Bob');
      final e1 = _msgEvent(
        eventId: r'$1:example.com',
        senderId: '@bob:example.com',
        ts: DateTime.utc(2024, 1, 1, 10),
        body: 'old',
      );
      final e2 = _msgEvent(
        eventId: r'$2:example.com',
        senderId: '@alice:example.com',
        ts: DateTime.utc(2024, 1, 2, 10),
        body: 'new',
      );
      // timeline.events is newest-first
      when(mockTimeline.events).thenReturn([e2, e1]);

      final exporter = RoomHistoryExporter(matrix: mockMatrix);
      final export = await exporter.export(
        roomId: '!room:example.com',
        options: const KoheraExportOptions(),
      );

      expect(export.messages.map((m) => m.eventId).toList(),
          [r'$1:example.com', r'$2:example.com']);
      expect(export.messages.first.senderDisplayname, 'Bob');
      expect(export.messages.last.senderDisplayname, 'Alice');
      expect(export.meta.displayname, 'Test Room');
      expect(export.meta.canonicalAlias, '#room:example.com');
    });

    test('filters out non-message state events', () async {
      user('@alice:example.com', 'Alice');
      final state = _stateEvent(
        eventId: r'$state:example.com',
        ts: DateTime.utc(2024),
      );
      final msg = _msgEvent(
        eventId: r'$1:example.com',
        senderId: '@alice:example.com',
        ts: DateTime.utc(2024, 1, 2),
      );
      when(mockTimeline.events).thenReturn([msg, state]);

      final exporter = RoomHistoryExporter(matrix: mockMatrix);
      final export = await exporter.export(
        roomId: '!room:example.com',
        options: const KoheraExportOptions(),
      );

      expect(export.messages, hasLength(1));
      expect(export.messages.single.eventId, r'$1:example.com');
    });

    test('applies date range filter', () async {
      user('@alice:example.com', 'Alice');
      final e1 = _msgEvent(
        eventId: r'$1:example.com',
        senderId: '@alice:example.com',
        ts: DateTime.utc(2024),
      );
      final e2 = _msgEvent(
        eventId: r'$2:example.com',
        senderId: '@alice:example.com',
        ts: DateTime.utc(2024, 6),
      );
      when(mockTimeline.events).thenReturn([e2, e1]);

      final exporter = RoomHistoryExporter(matrix: mockMatrix);
      final export = await exporter.export(
        roomId: '!room:example.com',
        options: KoheraExportOptions(
          start: DateTime.utc(2024, 3),
        ),
      );

      expect(export.messages, hasLength(1));
      expect(export.messages.single.eventId, r'$2:example.com');
    });

    test('includes media references when includeMedia true', () async {
      user('@alice:example.com', 'Alice');
      final media = _mediaEvent(
        eventId: r'$m:example.com',
        senderId: '@alice:example.com',
        ts: DateTime.utc(2024),
        mxcUrl: 'mxc://example.com/abc',
        fileName: 'pic.png',
        mimetype: 'image/png',
      );
      when(mockTimeline.events).thenReturn([media]);

      final exporter = RoomHistoryExporter(matrix: mockMatrix);
      final withMedia = await exporter.export(
        roomId: '!room:example.com',
        options: const KoheraExportOptions(
          includeMedia: true,
        ),
      );
      final withoutMedia = await exporter.export(
        roomId: '!room:example.com',
        options: const KoheraExportOptions(),
      );

      expect(withMedia.messages.single.hasMedia, isTrue);
      expect(withMedia.messages.single.mediaUrl, 'mxc://example.com/abc');
      expect(withoutMedia.messages.single.hasMedia, isFalse);
    });

    test('throws when room not found', () async {
      when(mockClient.getRoomById('!missing:example.com')).thenReturn(null);
      final exporter = RoomHistoryExporter(matrix: mockMatrix);
      expect(
        () => exporter.export(
          roomId: '!missing:example.com',
          options: const KoheraExportOptions(),
        ),
        throwsStateError,
      );
    });

    test('paginates history until canRequestHistory false', () async {
      user('@alice:example.com', 'Alice');
      final e1 = _msgEvent(
        eventId: r'$1:example.com',
        senderId: '@alice:example.com',
        ts: DateTime.utc(2024),
      );
      final e2 = _msgEvent(
        eventId: r'$2:example.com',
        senderId: '@alice:example.com',
        ts: DateTime.utc(2024, 1, 2),
      );
      when(mockTimeline.events).thenReturn([e2, e1]);
      var canRequest = true;
      when(mockTimeline.canRequestHistory).thenAnswer((_) => canRequest);
      when(mockTimeline.requestHistory(historyCount: anyNamed('historyCount')))
          .thenAnswer((_) async {
        canRequest = false;
      });

      final exporter = RoomHistoryExporter(matrix: mockMatrix);
      final export = await exporter.export(
        roomId: '!room:example.com',
        options: const KoheraExportOptions(),
      );

      verify(mockTimeline.requestHistory(
        historyCount: anyNamed('historyCount'),
      )).called(1);
      expect(export.messages, hasLength(2));
    });
  });
}
