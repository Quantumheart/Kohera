import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/chat/services/reply_preview_resolver.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([
  MockSpec<Event>(),
  MockSpec<User>(),
  MockSpec<Room>(),
  MockSpec<Timeline>(),
])
import 'reply_preview_resolver_test.mocks.dart';

void main() {
  late MockEvent event;
  late MockUser sender;
  late MockRoom room;

  setUp(() {
    event = MockEvent();
    sender = MockUser();
    room = MockRoom();

    when(event.eventId).thenReturn(r'$123:server');
    when(event.senderId).thenReturn('@alice:server');
    when(event.type).thenReturn(EventTypes.Message);
    when(event.senderFromMemoryOrFallback).thenReturn(sender);
    when(event.room).thenReturn(room);
    when(sender.displayName).thenReturn('Alice');
    when(event.content).thenReturn(<String, Object?>{
      'body': 'hello',
      'msgtype': 'm.text',
    });
    when(event.body).thenReturn('hello');
    when(event.messageType).thenReturn(MessageTypes.Text);
    when(event.redacted).thenReturn(false);
    when(event.formattedText).thenReturn('');
  });

  group('ReplyPreviewResolver.fromEvent', () {
    test('extracts sender name and body', () {
      final preview = const ReplyPreviewResolver().fromEvent(event);

      expect(preview.parentSenderName, 'Alice');
      expect(preview.parentBody, 'hello');
      expect(preview.parentMessageId, r'$123:server');
      expect(preview.parentSenderId, '@alice:server');
      expect(preview.parentFormattedHtml, isNull);
    });

    test('falls back to senderId when displayName is null', () {
      when(sender.displayName).thenReturn(null);

      final preview = const ReplyPreviewResolver().fromEvent(event);

      expect(preview.parentSenderName, '@alice:server');
    });

    test('strips reply fallback from body', () {
      when(event.body)
          .thenReturn('> <@bob:server> original\n\nreply text');

      final preview = const ReplyPreviewResolver().fromEvent(event);

      expect(preview.parentBody, 'reply text');
    });

    test('returns Unable to decrypt for bad-encrypted messages', () {
      when(event.messageType).thenReturn(MessageTypes.BadEncrypted);

      final preview = const ReplyPreviewResolver().fromEvent(event);

      expect(preview.parentBody, 'Unable to decrypt');
    });

    test('extracts formatted HTML when format is org.matrix.custom.html', () {
      when(event.formattedText).thenReturn('<b>hello</b>');
      when(event.content).thenReturn(<String, Object?>{
        'body': 'hello',
        'msgtype': 'm.text',
        'format': 'org.matrix.custom.html',
        'formatted_body': '<b>hello</b>',
      });

      final preview = const ReplyPreviewResolver().fromEvent(event);

      expect(preview.parentFormattedHtml, '<b>hello</b>');
    });

    test('returns null formattedHtml when format is not org.matrix.custom.html', () {
      when(event.formattedText).thenReturn('some text');
      when(event.content).thenReturn(<String, Object?>{
        'body': 'hello',
        'msgtype': 'm.text',
      });

      final preview = const ReplyPreviewResolver().fromEvent(event);

      expect(preview.parentFormattedHtml, isNull);
    });
  });

  group('ReplyPreviewResolver.resolveParent', () {
    test('returns preview when parent is available', () async {
      final timeline = MockTimeline();
      final parentEvent = MockEvent();
      final parentSender = MockUser();

      when(parentEvent.eventId).thenReturn(r'$parent:server');
      when(parentEvent.senderId).thenReturn('@bob:server');
      when(parentEvent.type).thenReturn(EventTypes.Message);
      when(parentEvent.senderFromMemoryOrFallback).thenReturn(parentSender);
      when(parentEvent.content).thenReturn(<String, Object?>{
        'body': 'parent message',
        'msgtype': 'm.text',
      });
      when(parentEvent.body).thenReturn('parent message');
      when(parentEvent.messageType).thenReturn(MessageTypes.Text);
      when(parentEvent.redacted).thenReturn(false);
      when(parentEvent.formattedText).thenReturn('');
      when(parentSender.displayName).thenReturn('Bob');
      when(event.getReplyEvent(timeline))
          .thenAnswer((_) async => parentEvent);

      final preview =
          await const ReplyPreviewResolver().resolveParent(event, timeline);

      expect(preview, isNotNull);
      expect(preview!.parentSenderName, 'Bob');
      expect(preview.parentBody, 'parent message');
      expect(preview.parentMessageId, r'$parent:server');
      expect(preview.parentSenderId, '@bob:server');
    });

    test('returns null when getReplyEvent throws', () async {
      final timeline = MockTimeline();
      when(event.getReplyEvent(timeline)).thenThrow(Exception('fail'));

      final preview =
          await const ReplyPreviewResolver().resolveParent(event, timeline);

      expect(preview, isNull);
    });

    test('returns null when parent is null', () async {
      final timeline = MockTimeline();
      when(event.getReplyEvent(timeline)).thenAnswer((_) async => null);

      final preview =
          await const ReplyPreviewResolver().resolveParent(event, timeline);

      expect(preview, isNull);
    });

    test('returns null when parent is redacted', () async {
      final timeline = MockTimeline();
      final parentEvent = MockEvent();
      when(parentEvent.type).thenReturn(EventTypes.Message);
      when(parentEvent.redacted).thenReturn(true);
      when(event.getReplyEvent(timeline))
          .thenAnswer((_) async => parentEvent);

      final preview =
          await const ReplyPreviewResolver().resolveParent(event, timeline);

      expect(preview, isNull);
    });

    test('returns null when parent is a redaction event', () async {
      final timeline = MockTimeline();
      final parentEvent = MockEvent();
      when(parentEvent.type).thenReturn(EventTypes.Redaction);
      when(parentEvent.redacted).thenReturn(false);
      when(event.getReplyEvent(timeline))
          .thenAnswer((_) async => parentEvent);

      final preview =
          await const ReplyPreviewResolver().resolveParent(event, timeline);

      expect(preview, isNull);
    });
  });
}
