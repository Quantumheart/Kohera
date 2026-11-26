import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/data/models/kohera_reply_preview.dart';
import 'package:kohera/data/repositories/message_repository.dart';
import 'package:kohera/data/repositories/room_repository.dart';
import 'package:kohera/features/chat/services/chat_message_actions.dart';
import 'package:kohera/features/chat/services/compose_state_controller.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([
  MockSpec<ScaffoldMessengerState>(),
  MockSpec<RoomRepository>(),
  MockSpec<MessageRepository>(),
])
import 'chat_message_actions_test.mocks.dart';

void main() {
  late MockScaffoldMessengerState mockScaffold;
  late MockRoomRepository mockRoomRepository;
  late MockMessageRepository mockMessageRepository;
  late ComposeStateController compose;
  late TextEditingController msgCtrl;
  late ChatMessageActions actions;

  setUp(() {
    mockScaffold = MockScaffoldMessengerState();
    mockRoomRepository = MockRoomRepository();
    mockMessageRepository = MockMessageRepository();
    compose = ComposeStateController();
    msgCtrl = TextEditingController();

    when(mockRoomRepository.userId).thenReturn('@me:example.com');
    actions = ChatMessageActions(
      getRoomId: () => '!room:example.com',
      compose: compose,
      msgCtrl: msgCtrl,
      getScaffold: () => mockScaffold,
      getRoomRepository: () => mockRoomRepository,
      getMessageRepository: () => mockMessageRepository,
    );
  });

  tearDown(() {
    compose.dispose();
    msgCtrl.dispose();
  });

  group('toggleReaction', () {
    test('delegates to the repository', () async {
      await actions.toggleReaction(r'$event1', '👍');

      verify(
        mockMessageRepository.toggleReaction(
          '!room:example.com',
          r'$event1',
          '👍',
        ),
      ).called(1);
    });

    test('shows snackbar on error', () async {
      when(
        mockMessageRepository.toggleReaction(any, any, any),
      ).thenThrow(Exception('network error'));

      await actions.toggleReaction(r'$event1', '👍');

      verify(mockScaffold.showSnackBar(any)).called(1);
    });
  });

  group('togglePin', () {
    test('pins an unpinned message', () async {
      when(mockRoomRepository.isPinned(any, any)).thenReturn(false);

      await actions.togglePin(r'$event1');

      verify(mockRoomRepository.setPinned(
        '!room:example.com',
        r'$event1',
        true,
      )).called(1);
    });

    test('unpins a pinned message', () async {
      when(mockRoomRepository.isPinned(any, any)).thenReturn(true);

      await actions.togglePin(r'$event1');

      verify(mockRoomRepository.setPinned(
        '!room:example.com',
        r'$event1',
        false,
      )).called(1);
    });

    test('shows snackbar on error', () async {
      when(mockRoomRepository.isPinned(any, any)).thenReturn(false);
      when(mockRoomRepository.setPinned(any, any, any))
          .thenThrow(Exception('permission denied'));

      await actions.togglePin(r'$event1');

      verify(mockScaffold.showSnackBar(any)).called(1);
    });
  });

  group('send', () {
    test('returns early when text and attachments are both empty', () async {
      msgCtrl.text = '';

      await actions.send();

      verifyNever(mockMessageRepository.sendText(any, any));
    });

    test('sends text and clears compose state', () async {
      msgCtrl.text = 'hello world';

      await actions.send();

      verify(mockMessageRepository.sendText(
        '!room:example.com',
        'hello world',
        inReplyToEventId: anyNamed('inReplyToEventId'),
        editEventId: anyNamed('editEventId'),
        threadRootEventId: anyNamed('threadRootEventId'),
        threadLastEventId: anyNamed('threadLastEventId'),
      )).called(1);
      expect(msgCtrl.text, isEmpty);
      expect(compose.replyNotifier.value, isNull);
      expect(compose.editNotifier.value, isNull);
    });

    test('sends with inReplyToEventId when reply is set', () async {
      compose.replyNotifier.value = const KoheraReplyPreview(
        parentMessageId: r'$reply1',
        parentSenderId: '@alice:example.com',
        parentSenderName: 'Alice',
        parentBody: 'hello',
      );
      msgCtrl.text = 'my reply';

      await actions.send();

      verify(mockMessageRepository.sendText(
        '!room:example.com',
        'my reply',
        inReplyToEventId: r'$reply1',
        editEventId: anyNamed('editEventId'),
        threadRootEventId: anyNamed('threadRootEventId'),
        threadLastEventId: anyNamed('threadLastEventId'),
      )).called(1);
    });

    test('sends with editEventId when edit is set', () async {
      compose.editNotifier.value = const KoheraReplyPreview(
        parentMessageId: r'$edit1',
        parentSenderId: '@me:example.com',
        parentSenderName: 'Me',
        parentBody: 'original',
      );
      msgCtrl.text = 'edited text';

      await actions.send();

      verify(mockMessageRepository.sendText(
        '!room:example.com',
        'edited text',
        inReplyToEventId: anyNamed('inReplyToEventId'),
        editEventId: r'$edit1',
        threadRootEventId: anyNamed('threadRootEventId'),
        threadLastEventId: anyNamed('threadLastEventId'),
      )).called(1);
    });

    test('restores compose state on send error', () async {
      msgCtrl.text = 'will fail';
      compose.replyNotifier.value = const KoheraReplyPreview(
        parentMessageId: r'$reply1',
        parentSenderId: '@alice:example.com',
        parentSenderName: 'Alice',
        parentBody: 'hello',
      );
      when(mockMessageRepository.sendText(
        any,
        any,
        inReplyToEventId: anyNamed('inReplyToEventId'),
        editEventId: anyNamed('editEventId'),
        threadRootEventId: anyNamed('threadRootEventId'),
        threadLastEventId: anyNamed('threadLastEventId'),
      )).thenThrow(Exception('send failed'));

      await actions.send();

      expect(msgCtrl.text, 'will fail');
      expect(compose.replyNotifier.value?.parentMessageId, r'$reply1');
      verify(mockScaffold.showSnackBar(any)).called(1);
    });
  });
}
