import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/models/pending_attachment.dart';
import 'package:kohera/features/chat/models/kohera_reply_preview.dart';
import 'package:kohera/features/chat/services/compose_state_controller.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([MockSpec<Event>(), MockSpec<Timeline>(), MockSpec<User>()])
import 'compose_state_controller_test.mocks.dart';

/// Stubs a [MockEvent] with enough fields for [ReplyPreviewResolver] to work.
MockEvent _stubEvent(
  MockEvent event, {
  String eventId = r'$event1',
  String body = 'hello',
  String senderId = '@alice:example.com',
  String senderName = 'Alice',
}) {
  final sender = MockUser();
  when(sender.displayName).thenReturn(senderName);
  when(sender.calcDisplayname()).thenReturn(senderName);
  when(sender.avatarUrl).thenReturn(null);
  when(event.eventId).thenReturn(eventId);
  when(event.senderId).thenReturn(senderId);
  when(event.body).thenReturn(body);
  when(event.formattedText).thenReturn('');
  when(event.content).thenReturn({'body': body, 'msgtype': 'm.text'});
  when(event.messageType).thenReturn('m.text');
  when(event.type).thenReturn(EventTypes.Message);
  when(event.senderFromMemoryOrFallback).thenReturn(sender);
  when(event.getDisplayEvent(any)).thenReturn(event);
  return event;
}

void main() {
  late ComposeStateController controller;
  late TextEditingController msgCtrl;

  setUp(() {
    controller = ComposeStateController();
    msgCtrl = TextEditingController();
  });

  tearDown(() {
    controller.dispose();
    msgCtrl.dispose();
  });

  group('reply', () {
    test('setReplyTo sets notifier value', () {
      final event = _stubEvent(MockEvent());
      controller.setReplyTo(event);
      expect(controller.replyNotifier.value, isA<KoheraReplyPreview>());
      expect(controller.replyNotifier.value?.parentMessageId, r'$event1');
    });

    test('cancelReply clears notifier value', () {
      controller.setReplyTo(_stubEvent(MockEvent()));
      controller.cancelReply();
      expect(controller.replyNotifier.value, isNull);
    });
  });

  group('edit', () {
    test('setEditEvent clears reply, sets edit, and populates msgCtrl', () {
      controller.setReplyTo(_stubEvent(MockEvent()));

      final editEvent =
          _stubEvent(MockEvent(), eventId: r'$edit1', body: 'hello world');
      controller.setEditEvent(editEvent, MockTimeline(), msgCtrl);

      expect(controller.replyNotifier.value, isNull);
      expect(controller.editNotifier.value, isA<KoheraReplyPreview>());
      expect(controller.editNotifier.value?.parentMessageId, r'$edit1');
      expect(msgCtrl.text, 'hello world');
      expect(msgCtrl.selection.baseOffset, 'hello world'.length);
    });

    test('setEditEvent strips reply fallback from body', () {
      final event = _stubEvent(
        MockEvent(),
        body: '> quoted\n\nactual reply',
      );
      controller.setEditEvent(event, MockTimeline(), msgCtrl);
      expect(msgCtrl.text, 'actual reply');
    });

    test('setEditEvent uses event directly when timeline is null', () {
      final event = _stubEvent(MockEvent(), body: 'direct body');
      controller.setEditEvent(event, null, msgCtrl);
      expect(controller.editNotifier.value?.parentMessageId, r'$event1');
      expect(msgCtrl.text, 'direct body');
    });

    test('cancelEdit clears edit and msgCtrl', () {
      final event = _stubEvent(MockEvent(), body: 'text');
      controller.setEditEvent(event, MockTimeline(), msgCtrl);
      controller.cancelEdit(msgCtrl);
      expect(controller.editNotifier.value, isNull);
      expect(msgCtrl.text, isEmpty);
    });
  });

  group('attachments', () {
    PendingAttachment makeAttachment({int size = 100}) {
      return PendingAttachment(
        bytes: Uint8List(size),
        name: 'file.png',
        isImage: true,
      );
    }

    test('addAttachment returns ok and appends', () {
      final result = controller.addAttachment(makeAttachment());
      expect(result, AddAttachmentResult.ok);
      expect(controller.pendingAttachments.value, hasLength(1));
    });

    test('addAttachment returns tooMany at limit', () {
      for (var i = 0; i < ComposeStateController.maxAttachments; i++) {
        controller.addAttachment(makeAttachment());
      }
      final result = controller.addAttachment(makeAttachment());
      expect(result, AddAttachmentResult.tooMany);
      expect(
        controller.pendingAttachments.value,
        hasLength(ComposeStateController.maxAttachments),
      );
    });

    test('addAttachment returns tooLarge over 25MB', () {
      final result = controller.addAttachment(
        makeAttachment(size: ComposeStateController.maxAttachmentBytes + 1),
      );
      expect(result, AddAttachmentResult.tooLarge);
      expect(controller.pendingAttachments.value, isEmpty);
    });

    test('removeAttachment removes by index', () {
      final a = PendingAttachment(
        bytes: Uint8List(1),
        name: 'a.png',
        isImage: true,
      );
      final b = PendingAttachment(
        bytes: Uint8List(1),
        name: 'b.png',
        isImage: true,
      );
      controller.addAttachment(a);
      controller.addAttachment(b);

      controller.removeAttachment(0);

      expect(controller.pendingAttachments.value, hasLength(1));
      expect(controller.pendingAttachments.value.first.name, 'b.png');
    });

    test('clearAttachments empties the list', () {
      controller.addAttachment(makeAttachment());
      controller.addAttachment(makeAttachment());
      controller.clearAttachments();
      expect(controller.pendingAttachments.value, isEmpty);
    });
  });

  group('thread', () {
    test('setThreadRoot sets notifier and clears reply', () {
      controller.setReplyTo(_stubEvent(MockEvent()));
      final root = MockEvent();
      controller.setThreadRoot(root);

      expect(controller.threadRootNotifier.value, root);
      expect(controller.replyNotifier.value, isNull);
    });

    test('clearThreadRoot clears notifier', () {
      controller.setThreadRoot(MockEvent());
      controller.clearThreadRoot();
      expect(controller.threadRootNotifier.value, isNull);
    });
  });

  group('reset', () {
    test('clears all state and msgCtrl', () {
      controller.setReplyTo(_stubEvent(MockEvent()));
      final editEvent = _stubEvent(MockEvent(), body: 'text');
      controller.setEditEvent(editEvent, MockTimeline(), msgCtrl);
      controller.setThreadRoot(MockEvent());
      controller.addAttachment(
        PendingAttachment(
          bytes: Uint8List(1),
          name: 'f.png',
          isImage: true,
        ),
      );

      controller.reset(msgCtrl);

      expect(controller.replyNotifier.value, isNull);
      expect(controller.editNotifier.value, isNull);
      expect(controller.threadRootNotifier.value, isNull);
      expect(controller.pendingAttachments.value, isEmpty);
      expect(msgCtrl.text, isEmpty);
    });
  });
}
