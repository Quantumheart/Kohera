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
}
