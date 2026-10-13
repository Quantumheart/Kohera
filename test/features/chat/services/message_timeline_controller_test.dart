import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/data/repositories/room_repository.dart';
import 'package:kohera/features/chat/services/message_timeline_controller.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<Room>(),
  MockSpec<Timeline>(),
  MockSpec<RoomRepository>(),
])
import 'message_timeline_controller_test.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockRoomRepository mockRooms;
  late MockRoom mockRoom;
  late MockTimeline mockTimeline;
  late MockClient mockClient;
  late MessageTimelineController controller;

  const roomId = '!room:example.com';

  setUp(() {
    mockRooms = MockRoomRepository();
    mockRoom = MockRoom();
    mockTimeline = MockTimeline();
    mockClient = MockClient();

    when(mockRooms.rawRoom(roomId)).thenReturn(mockRoom);
    when(mockRooms.userId).thenReturn('@me:example.com');
    when(mockRooms.ignoredUsers).thenReturn([]);
    when(mockRooms.encryption).thenReturn(null);
    when(mockRooms.searchClient).thenReturn(mockClient);
    when(mockRoom.id).thenReturn(roomId);
    when(mockRoom.client).thenReturn(mockClient);
    when(mockRoom.fullyRead).thenReturn('');
    when(mockRoom.notificationCount).thenReturn(0);
    when(mockRoom.receiptState).thenReturn(LatestReceiptState.empty());
    when(mockTimeline.events).thenReturn([]);
    when(mockTimeline.canRequestHistory).thenReturn(false);
    when(mockRoom.getTimeline(
      onUpdate: anyNamed('onUpdate'),
    )).thenAnswer((_) async => mockTimeline);

    controller = MessageTimelineController(
      rooms: mockRooms,
      roomId: roomId,
      sendPublicReadReceipts: false,
    );
  });

  tearDown(() => controller.dispose());

  group('isFragmented', () {
    test('reflects timeline.allowNewEvent', () async {
      await controller.init();
      when(mockTimeline.allowNewEvent).thenReturn(false);
      expect(controller.isFragmented, isTrue);

      when(mockTimeline.allowNewEvent).thenReturn(true);
      expect(controller.isFragmented, isFalse);
    });
  });

  group('reloadTimelineAtLive', () {
    test('cancels old timeline and loads live timeline without eventContextId',
        () async {
      await controller.init();
      when(mockTimeline.allowNewEvent).thenReturn(false);

      await controller.reloadTimelineAtLive();
      // Allow the post-frame / microtask to flush.
      await Future<void>.delayed(Duration.zero);

      verify(mockTimeline.cancelSubscriptions()).called(1);
      verify(mockRoom.getTimeline(
        onUpdate: anyNamed('onUpdate'),
      )).called(greaterThan(0));
      verifyNever(mockRoom.getTimeline(
        eventContextId: argThat(isNotNull, named: 'eventContextId'),
        onUpdate: anyNamed('onUpdate'),
      ));
    });
  });

  group('read marker', () {
    late void Function() onUpdate;

    setUp(() {
      final event = Event(
        content: {'body': 'hi', 'msgtype': MessageTypes.Text},
        type: EventTypes.Message,
        eventId: r'$latest',
        senderId: '@alice:example.com',
        originServerTs: DateTime(2026),
        room: mockRoom,
      );
      when(mockRoom.unsafeGetUserFromMemoryOrFallback('@alice:example.com'))
          .thenReturn(User('@alice:example.com', room: mockRoom));
      when(mockTimeline.events).thenReturn([event]);
      when(mockRoom.notificationCount).thenReturn(1);
      when(mockRoom.getTimeline(onUpdate: anyNamed('onUpdate')))
          .thenAnswer((invocation) async {
        onUpdate = invocation.namedArguments[#onUpdate] as void Function();
        return mockTimeline;
      });
    });

    tearDown(() {
      WidgetsBinding.instance
          .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });

    test('marks the room read while the app is in the foreground', () {
      fakeAsync((async) {
        WidgetsBinding.instance
            .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        unawaited(controller.init());
        async
          ..flushMicrotasks()
          ..elapse(const Duration(seconds: 2));

        verify(mockRoom.setReadMarker(r'$latest', mRead: anyNamed('mRead')))
            .called(1);
      });
    });

    for (final state in [AppLifecycleState.hidden, AppLifecycleState.paused]) {
      test('defers the read marker while $state until resumed', () {
        fakeAsync((async) {
          WidgetsBinding.instance
              .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
          unawaited(controller.init());
          async
            ..flushMicrotasks()
            ..elapse(const Duration(seconds: 2));
          clearInteractions(mockRoom);

          WidgetsBinding.instance.handleAppLifecycleStateChanged(state);
          onUpdate();
          async.elapse(const Duration(seconds: 5));
          verifyNever(
            mockRoom.setReadMarker(any, mRead: anyNamed('mRead')),
          );

          WidgetsBinding.instance
              .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
          async.elapse(const Duration(seconds: 2));
          verify(mockRoom.setReadMarker(r'$latest', mRead: anyNamed('mRead')))
              .called(1);
        });
      });
    }

    test('stops observing the app lifecycle after dispose', () {
      fakeAsync((async) {
        final disposable = MessageTimelineController(
          rooms: mockRooms,
          roomId: roomId,
          sendPublicReadReceipts: false,
        );
        WidgetsBinding.instance
            .handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        unawaited(disposable.init());
        async
          ..flushMicrotasks()
          ..elapse(const Duration(seconds: 2));
        disposable.dispose();

        WidgetsBinding.instance
            .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        async.elapse(const Duration(seconds: 2));

        verifyNever(mockRoom.setReadMarker(any, mRead: anyNamed('mRead')));
      });
    });
  });
}
