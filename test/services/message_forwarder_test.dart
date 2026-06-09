import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/features/chat/services/message_forwarder.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([
  MockSpec<Room>(),
  MockSpec<Event>(),
  MockSpec<Timeline>(),
])
import 'message_forwarder_test.mocks.dart';

void main() {
  group('buildForwardContent', () {
    test('strips relation metadata so the copy is standalone', () {
      final event = MockEvent();
      when(event.content).thenReturn({
        'msgtype': 'm.text',
        'body': 'hello',
        'm.relates_to': {
          'm.in_reply_to': {'event_id': r'$parent'},
        },
        'm.new_content': {'body': 'edited'},
      });

      final content = MessageForwarder.buildForwardContent(event);

      expect(content['body'], 'hello');
      expect(content['msgtype'], 'm.text');
      expect(content.containsKey('m.relates_to'), isFalse);
      expect(content.containsKey('m.new_content'), isFalse);
    });

    test('preserves media content (url/info) for forward-by-reference', () {
      final event = MockEvent();
      when(event.content).thenReturn({
        'msgtype': 'm.image',
        'body': 'cat.png',
        'url': 'mxc://example.com/abc',
        'info': {'mimetype': 'image/png'},
      });

      final content = MessageForwarder.buildForwardContent(event);

      expect(content['url'], 'mxc://example.com/abc');
      expect(content['msgtype'], 'm.image');
      expect(content['info'], isA<Map<String, dynamic>>());
    });

    test('does not mutate the source content map', () {
      final event = MockEvent();
      final original = <String, Object?>{
        'body': 'hi',
        'm.relates_to': {'rel': 1},
      };
      when(event.content).thenReturn(original);

      MessageForwarder.buildForwardContent(event);

      expect(original.containsKey('m.relates_to'), isTrue);
    });
  });

  group('forward', () {
    test('sends the display event content with its type to the target', () async {
      final event = MockEvent();
      final display = MockEvent();
      final timeline = MockTimeline();
      final target = MockRoom();

      when(event.getDisplayEvent(timeline)).thenReturn(display);
      when(display.type).thenReturn('m.room.message');
      when(display.content).thenReturn({'msgtype': 'm.text', 'body': 'hi'});

      await MessageForwarder.forward(
        event: event,
        target: target,
        timeline: timeline,
      );

      final call = verify(
        target.sendEvent(captureAny, type: captureAnyNamed('type')),
      );
      final content = call.captured[0] as Map<String, dynamic>;
      final type = call.captured[1] as String;
      expect(type, 'm.room.message');
      expect(content['body'], 'hi');
    });

    test('forwards the event directly when no timeline is given', () async {
      final event = MockEvent();
      final target = MockRoom();

      when(event.type).thenReturn('m.sticker');
      when(event.content).thenReturn({'body': 'sticker', 'url': 'mxc://x/y'});

      await MessageForwarder.forward(event: event, target: target);

      verifyNever(event.getDisplayEvent(any));
      verify(target.sendEvent(any, type: 'm.sticker')).called(1);
    });
  });
}
