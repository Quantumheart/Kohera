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

  group('canRequestFuture / isFragmented', () {
    test('reflect timeline.allowNewEvent and canRequestFuture', () async {
      await controller.init();
      when(mockTimeline.allowNewEvent).thenReturn(false);
      when(mockTimeline.canRequestFuture).thenReturn(true);
      expect(controller.isFragmented, isTrue);
      expect(controller.canRequestFuture, isTrue);

      when(mockTimeline.allowNewEvent).thenReturn(true);
      when(mockTimeline.canRequestFuture).thenReturn(false);
      expect(controller.isFragmented, isFalse);
      expect(controller.canRequestFuture, isFalse);
    });
  });

  group('loadNewer', () {
    test('no-op when canRequestFuture is false', () async {
      await controller.init();
      when(mockTimeline.canRequestFuture).thenReturn(false);

      await controller.loadNewer(shouldContinue: () => true);

      verifyNever(mockTimeline.requestFuture(
        historyCount: anyNamed('historyCount'),
        filter: anyNamed('filter'),
      ));
      expect(controller.isLoadingFuture, isFalse);
    });

    test('calls requestFuture once when shouldContinue stops the loop',
        () async {
      await controller.init();
      when(mockTimeline.canRequestFuture).thenReturn(true);
      when(mockTimeline.requestFuture(
        historyCount: anyNamed('historyCount'),
        filter: anyNamed('filter'),
      )).thenAnswer((_) async {});

      await controller.loadNewer(shouldContinue: () => false);

      verify(mockTimeline.requestFuture(
        historyCount: anyNamed('historyCount'),
        filter: anyNamed('filter'),
      )).called(1);
      expect(controller.isLoadingFuture, isFalse);
    });

    test('loops until shouldContinue returns false', () async {
      await controller.init();
      var calls = 0;
      when(mockTimeline.canRequestFuture).thenAnswer((_) => calls < 3);
      when(mockTimeline.requestFuture(
        historyCount: anyNamed('historyCount'),
        filter: anyNamed('filter'),
      )).thenAnswer((_) async {
        calls++;
      });

      await controller.loadNewer(shouldContinue: () => calls < 3);

      verify(mockTimeline.requestFuture(
        historyCount: anyNamed('historyCount'),
        filter: anyNamed('filter'),
      )).called(3);
    });

    test('skipped for thread timelines', () async {
      final threadController = MessageTimelineController(
        rooms: mockRooms,
        roomId: roomId,
        sendPublicReadReceipts: false,
        threadRootEventId: r'$root:example.com',
      );
      addTearDown(threadController.dispose);
      await threadController.init();
      when(mockTimeline.canRequestFuture).thenReturn(true);

      await threadController.loadNewer(shouldContinue: () => true);

      verifyNever(mockTimeline.requestFuture(
        historyCount: anyNamed('historyCount'),
        filter: anyNamed('filter'),
      ));
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
}
