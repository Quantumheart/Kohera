import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/core/services/sub_services/presence_service.dart';
import 'package:kohera/core/state/selection_controller.dart';
import 'package:kohera/data/models/kohera_push_rule_state.dart';
import 'package:kohera/data/repositories/media_repository.dart';
import 'package:kohera/data/repositories/room_repository.dart';
import 'package:kohera/data/repositories/space_tree_repository.dart';
import 'package:kohera/data/repositories/user_repository.dart';
import 'package:kohera/data/services/avatar_resolver.dart';
import 'package:kohera/data/services/matrix_client_service.dart';
import 'package:kohera/features/rooms/services/room_details_controller.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([
  MockSpec<Client>(),
  MockSpec<Room>(),
  MockSpec<MatrixService>(),
  MockSpec<SpaceTreeRepository>(),
  MockSpec<AvatarResolver>(),
  MockSpec<PresenceService>(),
])
import 'room_details_controller_test.mocks.dart';

void main() {
  late MockMatrixService mockMatrix;
  late MockClient mockClient;
  late MockRoom mockRoom;
  late MockSpaceTreeRepository mockSelection;
  late SelectionController selectionController;
  late MockPresenceService mockPresence;
  late MockAvatarResolver mockAvatarResolver;
  late CachedStreamController<SyncUpdate> syncCtl;
  late RoomRepository roomRepo;
  late UserRepository userRepo;
  late MediaRepository mediaRepo;

  const roomId = '!room:example.com';

  setUp(() {
    mockMatrix = MockMatrixService();
    mockClient = MockClient();
    mockRoom = MockRoom();
    mockSelection = MockSpaceTreeRepository();
    selectionController = SelectionController(clientService: MatrixClientService(mockClient));
    mockPresence = MockPresenceService();
    mockAvatarResolver = MockAvatarResolver();
    syncCtl = CachedStreamController<SyncUpdate>();

    when(mockMatrix.matrixClientService).thenReturn(MatrixClientService(mockClient));
    when(mockMatrix.spaceTree).thenReturn(mockSelection);
    when(mockMatrix.avatarResolver).thenReturn(mockAvatarResolver);
    when(mockClient.getRoomById(roomId)).thenReturn(mockRoom);
    when(mockClient.onSync).thenReturn(syncCtl);
    when(mockClient.userID).thenReturn('@me:example.com');
    when(mockRoom.id).thenReturn(roomId);
    when(mockRoom.client).thenReturn(mockClient);
    when(mockRoom.encrypted).thenReturn(false);
    when(mockRoom.isDirectChat).thenReturn(false);
    when(mockRoom.isFavourite).thenReturn(false);
    when(mockRoom.pushRuleState).thenReturn(PushRuleState.notify);
    when(mockRoom.canBan).thenReturn(false);
    when(mockRoom.participantListComplete).thenReturn(false);
    when(mockRoom.summary).thenReturn(RoomSummary.fromJson({}));
    when(mockRoom.getLocalizedDisplayname()).thenReturn('Test Room');
    when(mockRoom.setPushRuleState(any)).thenAnswer((_) async {});
    when(mockRoom.setFavourite(any)).thenAnswer((_) async {});
    when(mockRoom.invite(any)).thenAnswer((_) async {});
    when(mockRoom.setName(any)).thenAnswer((_) async => '');
    when(mockRoom.setDescription(any)).thenAnswer((_) async => '');
    when(mockRoom.enableEncryption()).thenAnswer((_) async {});
    when(mockRoom.leave()).thenAnswer((_) async {});
    when(mockClient.updateUserDeviceKeys()).thenAnswer((_) async {});

    roomRepo = RoomRepository(clientService: mockMatrix.matrixClientService);
    userRepo = UserRepository(clientService: mockMatrix.matrixClientService, presenceOverride: mockPresence);
    mediaRepo = MediaRepository(avatarResolver: mockMatrix.avatarResolver, mediaResolver: mockMatrix.mediaResolver);
  });

  group('RoomDetailsController getters with room', () {
    test('hasRoom is true after init', () {
      final ctrl = RoomDetailsController(
        roomId: roomId,
        roomRepo: roomRepo,
        userRepo: userRepo,
        mediaRepo: mediaRepo,
        presence: userRepo,
        selection: selectionController,
      );
      ctrl.init();
      expect(ctrl.hasRoom, isTrue);
      ctrl.dispose();
    });

    test('hasRoom is false when room not found', () {
      when(mockClient.getRoomById(roomId)).thenReturn(null);
      final ctrl = RoomDetailsController(
        roomId: roomId,
        roomRepo: roomRepo,
        userRepo: userRepo,
        mediaRepo: mediaRepo,
        presence: userRepo,
        selection: selectionController,
      );
      ctrl.init();
      expect(ctrl.hasRoom, isFalse);
      ctrl.dispose();
    });

    test('summary returns from selection', () {
      final ctrl = RoomDetailsController(
        roomId: roomId,
        roomRepo: roomRepo,
        userRepo: userRepo,
        mediaRepo: mediaRepo,
        presence: userRepo,
        selection: selectionController,
      );
      ctrl.init();
      expect(ctrl.summary, isNotNull);
      expect(ctrl.summary!.displayname, 'Test Room');
      ctrl.dispose();
    });

    test('encrypted reflects room', () {
      final ctrl = RoomDetailsController(
        roomId: roomId,
        roomRepo: roomRepo,
        userRepo: userRepo,
        mediaRepo: mediaRepo,
        presence: userRepo,
        selection: selectionController,
      );
      ctrl.init();
      expect(ctrl.encrypted, isFalse);
      ctrl.dispose();
    });

    test('isFavourite reflects room', () {
      final ctrl = RoomDetailsController(
        roomId: roomId,
        roomRepo: roomRepo,
        userRepo: userRepo,
        mediaRepo: mediaRepo,
        presence: userRepo,
        selection: selectionController,
      );
      ctrl.init();
      expect(ctrl.isFavourite, isFalse);
      ctrl.dispose();
    });

    test('isMuted is true when pushRuleState is dontNotify', () {
      when(mockRoom.pushRuleState).thenReturn(PushRuleState.dontNotify);
      final ctrl = RoomDetailsController(
        roomId: roomId,
        roomRepo: roomRepo,
        userRepo: userRepo,
        mediaRepo: mediaRepo,
        presence: userRepo,
        selection: selectionController,
      );
      ctrl.init();
      expect(ctrl.isMuted, isTrue);
      ctrl.dispose();
    });

    test('pushRuleState maps correctly', () {
      final ctrl = RoomDetailsController(
        roomId: roomId,
        roomRepo: roomRepo,
        userRepo: userRepo,
        mediaRepo: mediaRepo,
        presence: userRepo,
        selection: selectionController,
      );
      ctrl.init();
      expect(ctrl.pushRuleState, KoheraPushRuleState.notify);
      ctrl.dispose();
    });

    test('canBan reflects room', () {
      final ctrl = RoomDetailsController(
        roomId: roomId,
        roomRepo: roomRepo,
        userRepo: userRepo,
        mediaRepo: mediaRepo,
        presence: userRepo,
        selection: selectionController,
      );
      ctrl.init();
      expect(ctrl.canBan, isFalse);
      ctrl.dispose();
    });
  });

  group('RoomDetailsController getters without room', () {
    test('all getters return defaults when room is null', () {
      when(mockClient.getRoomById(roomId)).thenReturn(null);
      final ctrl = RoomDetailsController(
        roomId: roomId,
        roomRepo: roomRepo,
        userRepo: userRepo,
        mediaRepo: mediaRepo,
        presence: userRepo,
        selection: selectionController,
      );
      // Don't call init — room is null
      expect(ctrl.hasRoom, isFalse);
      expect(ctrl.summary, isNull);
      expect(ctrl.encrypted, isFalse);
      expect(ctrl.isFavourite, isFalse);
      expect(ctrl.canBan, isFalse);
      expect(ctrl.isDirectChat, isFalse);
      expect(ctrl.partnerId, isNull);
      expect(ctrl.deviceKeys, isEmpty);
      expect(ctrl.participantListComplete, isFalse);
      ctrl.dispose();
    });
  });

  group('RoomDetailsController actions', () {
    test('toggleMute switches from notify to dontNotify', () async {
      final ctrl = RoomDetailsController(
        roomId: roomId,
        roomRepo: roomRepo,
        userRepo: userRepo,
        mediaRepo: mediaRepo,
        presence: userRepo,
        selection: selectionController,
      );
      ctrl.init();
      await ctrl.toggleMute();
      verify(mockRoom.setPushRuleState(PushRuleState.dontNotify)).called(1);
      ctrl.dispose();
    });

    test('toggleMute switches from dontNotify to notify', () async {
      when(mockRoom.pushRuleState).thenReturn(PushRuleState.dontNotify);
      final ctrl = RoomDetailsController(
        roomId: roomId,
        roomRepo: roomRepo,
        userRepo: userRepo,
        mediaRepo: mediaRepo,
        presence: userRepo,
        selection: selectionController,
      );
      ctrl.init();
      await ctrl.toggleMute();
      verify(mockRoom.setPushRuleState(PushRuleState.notify)).called(1);
      ctrl.dispose();
    });

    test('setPushRule calls setPushRuleState', () async {
      final ctrl = RoomDetailsController(
        roomId: roomId,
        roomRepo: roomRepo,
        userRepo: userRepo,
        mediaRepo: mediaRepo,
        presence: userRepo,
        selection: selectionController,
      );
      ctrl.init();
      await ctrl.setPushRule(KoheraPushRuleState.mentionsOnly);
      verify(mockRoom.setPushRuleState(PushRuleState.mentionsOnly)).called(1);
      ctrl.dispose();
    });

    test('invite calls room.invite', () async {
      final ctrl = RoomDetailsController(
        roomId: roomId,
        roomRepo: roomRepo,
        userRepo: userRepo,
        mediaRepo: mediaRepo,
        presence: userRepo,
        selection: selectionController,
      );
      ctrl.init();
      await ctrl.invite('@user:example.com');
      verify(mockRoom.invite('@user:example.com')).called(1);
      ctrl.dispose();
    });

    test('setName calls room.setName', () async {
      final ctrl = RoomDetailsController(
        roomId: roomId,
        roomRepo: roomRepo,
        userRepo: userRepo,
        mediaRepo: mediaRepo,
        presence: userRepo,
        selection: selectionController,
      );
      ctrl.init();
      await ctrl.setName('New Name');
      verify(mockRoom.setName('New Name')).called(1);
      ctrl.dispose();
    });

    test('setDescription calls room.setDescription', () async {
      final ctrl = RoomDetailsController(
        roomId: roomId,
        roomRepo: roomRepo,
        userRepo: userRepo,
        mediaRepo: mediaRepo,
        presence: userRepo,
        selection: selectionController,
      );
      ctrl.init();
      await ctrl.setDescription('New topic');
      verify(mockRoom.setDescription('New topic')).called(1);
      ctrl.dispose();
    });

    test('enableEncryption calls room.enableEncryption', () async {
      final ctrl = RoomDetailsController(
        roomId: roomId,
        roomRepo: roomRepo,
        userRepo: userRepo,
        mediaRepo: mediaRepo,
        presence: userRepo,
        selection: selectionController,
      );
      ctrl.init();
      await ctrl.enableEncryption();
      verify(mockRoom.enableEncryption()).called(1);
      ctrl.dispose();
    });

    test('leave calls room.leave and selects null', () async {
      final ctrl = RoomDetailsController(
        roomId: roomId,
        roomRepo: roomRepo,
        userRepo: userRepo,
        mediaRepo: mediaRepo,
        presence: userRepo,
        selection: selectionController,
      );
      ctrl.init();
      selectionController.selectRoom('!room:example.com');
      await ctrl.leave();
      verify(mockRoom.leave()).called(1);
      expect(selectionController.selectedRoomId, isNull);
      ctrl.dispose();
    });

    test('toggleFavourite calls setFavourite', () async {
      when(mockRoom.isFavourite).thenReturn(false);
      final ctrl = RoomDetailsController(
        roomId: roomId,
        roomRepo: roomRepo,
        userRepo: userRepo,
        mediaRepo: mediaRepo,
        presence: userRepo,
        selection: selectionController,
      );
      ctrl.init();
      await ctrl.toggleFavourite();
      verify(mockRoom.setFavourite(true)).called(1);
      ctrl.dispose();
    });
  });

  group('RoomDetailsController lifecycle', () {
    test('init with null room notifies listeners', () {
      when(mockClient.getRoomById(roomId)).thenReturn(null);
      final ctrl = RoomDetailsController(
        roomId: roomId,
        roomRepo: roomRepo,
        userRepo: userRepo,
        mediaRepo: mediaRepo,
        presence: userRepo,
        selection: selectionController,
      );
      var notified = false;
      ctrl.addListener(() => notified = true);
      ctrl.init();
      expect(notified, isTrue);
      ctrl.dispose();
    });

    test('checkRoomChanged picks up new room', () {
      when(mockClient.getRoomById(roomId)).thenReturn(null);
      final ctrl = RoomDetailsController(
        roomId: roomId,
        roomRepo: roomRepo,
        userRepo: userRepo,
        mediaRepo: mediaRepo,
        presence: userRepo,
        selection: selectionController,
      );
      ctrl.init();
      expect(ctrl.hasRoom, isFalse);

      // Room appears
      when(mockClient.getRoomById(roomId)).thenReturn(mockRoom);

      ctrl.checkRoomChanged();
      expect(ctrl.hasRoom, isTrue);
      ctrl.dispose();
    });

    test('dispose cancels subscriptions', () {
      final ctrl = RoomDetailsController(
        roomId: roomId,
        roomRepo: roomRepo,
        userRepo: userRepo,
        mediaRepo: mediaRepo,
        presence: userRepo,
        selection: selectionController,
      );
      ctrl.init();
      ctrl.dispose();
      // No throw = pass
    });
  });

  group('RoomDetailsController push rule mapping', () {
    test('notify maps both ways', () {
      final ctrl = RoomDetailsController(
        roomId: roomId,
        roomRepo: roomRepo,
        userRepo: userRepo,
        mediaRepo: mediaRepo,
        presence: userRepo,
        selection: selectionController,
      );
      ctrl.init();
      expect(ctrl.pushRuleState, KoheraPushRuleState.notify);
      ctrl.dispose();
    });

    test('dontNotify maps to dontNotify', () {
      when(mockRoom.pushRuleState).thenReturn(PushRuleState.dontNotify);
      final ctrl = RoomDetailsController(
        roomId: roomId,
        roomRepo: roomRepo,
        userRepo: userRepo,
        mediaRepo: mediaRepo,
        presence: userRepo,
        selection: selectionController,
      );
      ctrl.init();
      expect(ctrl.pushRuleState, KoheraPushRuleState.dontNotify);
      ctrl.dispose();
    });

    test('mentionsOnly maps to mentionsOnly', () {
      when(mockRoom.pushRuleState).thenReturn(PushRuleState.mentionsOnly);
      final ctrl = RoomDetailsController(
        roomId: roomId,
        roomRepo: roomRepo,
        userRepo: userRepo,
        mediaRepo: mediaRepo,
        presence: userRepo,
        selection: selectionController,
      );
      ctrl.init();
      expect(ctrl.pushRuleState, KoheraPushRuleState.mentionsOnly);
      ctrl.dispose();
    });
  });
}
