import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/data/repositories/room_repository.dart';
import 'package:kohera/features/chat/services/typing_controller.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([MockSpec<RoomRepository>()])
import 'typing_controller_test.mocks.dart';

const _roomId = '!test:example.com';

void main() {
  late MockRoomRepository rooms;

  setUp(() {
    rooms = MockRoomRepository();
    when(rooms.setTyping(any, any, timeoutMs: anyNamed('timeoutMs')))
        .thenAnswer((_) async {});
  });

  group('TypingController', () {
    test('onTextChanged sends typing true', () {
      fakeAsync((async) {
        final ctrl = TypingController(roomId: _roomId, rooms: rooms);
        ctrl.onTextChanged('hello');

        verify(rooms.setTyping(_roomId, true, timeoutMs: 30000)).called(1);

        ctrl.dispose();
      });
    });

    test('rapid calls within 4s do not re-send', () {
      fakeAsync((async) {
        final ctrl = TypingController(roomId: _roomId, rooms: rooms);
        ctrl.onTextChanged('h');
        ctrl.onTextChanged('he');
        ctrl.onTextChanged('hel');

        verify(rooms.setTyping(_roomId, true, timeoutMs: 30000)).called(1);

        ctrl.dispose();
      });
    });

    test('re-sends after 4s+ elapsed', () {
      fakeAsync((async) {
        final ctrl = TypingController(roomId: _roomId, rooms: rooms);
        ctrl.onTextChanged('h');

        async.elapse(const Duration(seconds: 5));

        ctrl.onTextChanged('he');

        verify(rooms.setTyping(_roomId, true, timeoutMs: 30000)).called(2);

        ctrl.dispose();
      });
    });

    test('stop sends false', () {
      fakeAsync((async) {
        final ctrl = TypingController(roomId: _roomId, rooms: rooms);
        ctrl.onTextChanged('hello');

        ctrl.stop();

        verify(rooms.setTyping(_roomId, false)).called(1);

        ctrl.dispose();
      });
    });

    test('stop is idempotent', () {
      fakeAsync((async) {
        final ctrl = TypingController(roomId: _roomId, rooms: rooms);
        ctrl.onTextChanged('hello');

        ctrl.stop();
        ctrl.stop();

        verify(rooms.setTyping(_roomId, false)).called(1);

        ctrl.dispose();
      });
    });

    test('30s inactivity auto-stops', () {
      fakeAsync((async) {
        final ctrl = TypingController(roomId: _roomId, rooms: rooms);
        ctrl.onTextChanged('hello');

        async.elapse(const Duration(seconds: 30));

        verify(rooms.setTyping(_roomId, false)).called(1);

        ctrl.dispose();
      });
    });

    test('empty text triggers stop', () {
      fakeAsync((async) {
        final ctrl = TypingController(roomId: _roomId, rooms: rooms);
        ctrl.onTextChanged('hello');

        ctrl.onTextChanged('');

        verify(rooms.setTyping(_roomId, false)).called(1);

        ctrl.dispose();
      });
    });

    test('dispose calls stop', () {
      fakeAsync((async) {
        final ctrl = TypingController(roomId: _roomId, rooms: rooms);
        ctrl.onTextChanged('hello');

        ctrl.dispose();

        verify(rooms.setTyping(_roomId, false)).called(1);
      });
    });

    test('remains consistent when setTyping throws', () {
      fakeAsync((async) {
        when(rooms.setTyping(any, true, timeoutMs: anyNamed('timeoutMs')))
            .thenAnswer((_) async => throw Exception('network error'));

        final ctrl = TypingController(roomId: _roomId, rooms: rooms);
        ctrl.onTextChanged('hello');
        async.flushMicrotasks();

        // Controller should still consider itself typing despite the error,
        // so a subsequent call within 4s should be debounced.
        ctrl.onTextChanged('hello!');
        verify(rooms.setTyping(_roomId, true, timeoutMs: 30000)).called(1);

        // After 4s+ it should re-send.
        async.elapse(const Duration(seconds: 5));
        ctrl.onTextChanged('hello!!');
        verify(rooms.setTyping(_roomId, true, timeoutMs: 30000)).called(1);

        ctrl.dispose();
      });
    });
  });
}
