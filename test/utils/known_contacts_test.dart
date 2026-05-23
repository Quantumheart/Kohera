import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/utils/known_contacts.dart';
import 'package:matrix/matrix.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

@GenerateNiceMocks([MockSpec<Client>(), MockSpec<Room>(), MockSpec<User>()])
import 'known_contacts_test.mocks.dart';

MockRoom _makeRoom({
  required bool isDirect,
  String? directChatMxid,
  String displayName = 'Room',
  Uri? avatar,
}) {
  final room = MockRoom();
  when(room.isDirectChat).thenReturn(isDirect);
  when(room.directChatMatrixID).thenReturn(directChatMxid);
  when(room.getLocalizedDisplayname()).thenReturn(displayName);
  when(room.avatar).thenReturn(avatar);
  return room;
}

MockRoom _makeGroupRoom(List<MockUser> participants, {int memberCount = 0}) {
  final room = MockRoom();
  when(room.isDirectChat).thenReturn(false);
  when(room.getParticipants()).thenReturn(participants);
  when(room.summary).thenReturn(RoomSummary.fromJson({
    'm.joined_member_count': memberCount,
    'm.invited_member_count': 0,
  }),);
  return room;
}

MockUser _makeUser(String id, {String? displayName}) {
  final user = MockUser();
  when(user.id).thenReturn(id);
  when(user.displayName).thenReturn(displayName);
  when(user.avatarUrl).thenReturn(null);
  return user;
}

void main() {
  late MockClient client;

  setUp(() {
    client = MockClient();
  });

  test('returns empty list when client has no rooms', () {
    when(client.rooms).thenReturn([]);
    expect(knownContacts(client), isEmpty);
  });

  test('skips non-direct-chat rooms', () {
    final room = _makeRoom(isDirect: false, directChatMxid: '@user:example.com');
    when(client.rooms).thenReturn([room]);
    expect(knownContacts(client), isEmpty);
  });

  test('skips direct rooms with null matrixID', () {
    final room = _makeRoom(isDirect: true);
    when(client.rooms).thenReturn([room]);
    expect(knownContacts(client), isEmpty);
  });

  test('returns profile for a single DM room', () {
    final avatar = Uri.parse('mxc://example.com/abc');
    final room = _makeRoom(
      isDirect: true,
      directChatMxid: '@alice:example.com',
      displayName: 'Alice',
      avatar: avatar,
    );
    when(client.rooms).thenReturn([room]);

    final result = knownContacts(client);
    expect(result, hasLength(1));
    expect(result[0].userId, '@alice:example.com');
    expect(result[0].displayName, 'Alice');
    expect(result[0].avatarUrl, avatar);
  });

  test('deduplicates contacts with the same matrixID', () {
    final rooms = [
      _makeRoom(
        isDirect: true,
        directChatMxid: '@bob:example.com',
        displayName: 'Bob (old)',
      ),
      _makeRoom(
        isDirect: true,
        directChatMxid: '@bob:example.com',
        displayName: 'Bob (new)',
      ),
    ];
    when(client.rooms).thenReturn(rooms);

    final result = knownContacts(client);
    expect(result, hasLength(1));
    expect(result[0].displayName, 'Bob (old)');
  });

  test('returns multiple distinct contacts', () {
    final rooms = [
      _makeRoom(isDirect: true, directChatMxid: '@a:x.com', displayName: 'A'),
      _makeRoom(isDirect: false, directChatMxid: '@skip:x.com'),
      _makeRoom(isDirect: true, directChatMxid: '@b:x.com', displayName: 'B'),
      _makeRoom(isDirect: true, directChatMxid: '@c:x.com', displayName: 'C'),
    ];
    when(client.rooms).thenReturn(rooms);

    final result = knownContacts(client);
    expect(result, hasLength(3));
    expect(result.map((p) => p.userId), ['@a:x.com', '@b:x.com', '@c:x.com']);
  });

  group('roomContacts', () {
    test('returns empty list when client has no group rooms', () {
      when(client.rooms).thenReturn([]);
      when(client.userID).thenReturn('@me:example.com');
      expect(roomContacts(client), isEmpty);
    });

    test('excludes the client own user ID', () {
      when(client.userID).thenReturn('@me:example.com');
      final me = _makeUser('@me:example.com', displayName: 'Me');
      final alice = _makeUser('@alice:example.com', displayName: 'Alice');
      final room = _makeGroupRoom([me, alice], memberCount: 2);
      when(client.rooms).thenReturn([room]);

      final result = roomContacts(client);
      expect(result.map((p) => p.userId), ['@alice:example.com']);
    });

    test('excludes MXIDs in excludeMxids', () {
      when(client.userID).thenReturn('@me:example.com');
      final alice = _makeUser('@alice:example.com');
      final bob = _makeUser('@bob:example.com');
      final room = _makeGroupRoom([alice, bob], memberCount: 2);
      when(client.rooms).thenReturn([room]);

      final result = roomContacts(client, excludeMxids: {'@alice:example.com'});
      expect(result.map((p) => p.userId), ['@bob:example.com']);
    });

    test('includes members from joined group rooms', () {
      when(client.userID).thenReturn('@me:example.com');
      final alice = _makeUser('@alice:example.com', displayName: 'Alice');
      final room = _makeGroupRoom([alice], memberCount: 1);
      when(client.rooms).thenReturn([room]);

      final result = roomContacts(client);
      expect(result, hasLength(1));
      expect(result[0].userId, '@alice:example.com');
      expect(result[0].displayName, 'Alice');
    });

    test('deduplicates members appearing in multiple rooms', () {
      when(client.userID).thenReturn('@me:example.com');
      final alice = _makeUser('@alice:example.com');
      final room1 = _makeGroupRoom([alice], memberCount: 2);
      final room2 = _makeGroupRoom([alice], memberCount: 3);
      when(client.rooms).thenReturn([room1, room2]);

      final result = roomContacts(client);
      expect(result, hasLength(1));
    });

    test('caps results at limit', () {
      when(client.userID).thenReturn('@me:example.com');
      final users = List.generate(10, (i) => _makeUser('@user$i:example.com'));
      final room = _makeGroupRoom(users, memberCount: 10);
      when(client.rooms).thenReturn([room]);

      final result = roomContacts(client, limit: 3);
      expect(result, hasLength(3));
    });

    test('skips DM rooms', () {
      when(client.userID).thenReturn('@me:example.com');
      final dmRoom = _makeRoom(isDirect: true, directChatMxid: '@alice:example.com');
      when(client.rooms).thenReturn([dmRoom]);

      expect(roomContacts(client), isEmpty);
    });
  });
}
