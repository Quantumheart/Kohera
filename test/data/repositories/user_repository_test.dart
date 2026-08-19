import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/data/repositories/user_repository.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/mockito.dart';

import '../../services/matrix_service_test.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockClient mockClient;
  late MockFlutterSecureStorage mockStorage;
  late MatrixService service;
  late UserRepository repo;

  setUp(() {
    mockClient = MockClient();
    mockStorage = MockFlutterSecureStorage();
    when(mockClient.rooms).thenReturn([]);
    when(mockClient.onSync).thenReturn(CachedStreamController<SyncUpdate>());
    when(mockClient.onPresenceChanged)
        .thenReturn(CachedStreamController<CachedPresence>());
    when(mockClient.database).thenReturn(_FakeDatabase());
    service = MatrixService(
      client: mockClient,
      storage: mockStorage,
      clientName: 'test',
    );
    repo = UserRepository(matrix: service);
  });

  group('userId', () {
    test('returns client userID', () {
      when(mockClient.userID).thenReturn('@me:example.com');
      expect(repo.userId, '@me:example.com');
    });

    test('returns null when not logged in', () {
      when(mockClient.userID).thenReturn(null);
      expect(repo.userId, isNull);
    });
  });

  group('deviceId', () {
    test('returns client deviceID', () {
      when(mockClient.deviceID).thenReturn('ABCD12');
      expect(repo.deviceId, 'ABCD12');
    });
  });

  group('deviceKeysFor', () {
    test('returns empty list when no device keys', () {
      when(mockClient.userDeviceKeys).thenReturn({});
      expect(repo.deviceKeysFor('@partner:example.com'), isEmpty);
    });
  });

  group('loadDevices', () {
    test('returns empty list when client returns null', () async {
      when(mockClient.getDevices()).thenAnswer((_) async => null);
      expect(await repo.loadDevices(), isEmpty);
    });
  });

  group('ignoredUsers', () {
    test('returns client ignoredUsers', () {
      when(mockClient.ignoredUsers).thenReturn(['@spammer:example.com']);
      expect(repo.ignoredUsers, ['@spammer:example.com']);
    });
  });

  group('presence', () {
    test('returns MatrixService presence', () {
      expect(repo.presence, isNotNull);
    });
  });

  group('notifyListeners', () {
    test('notifies on MatrixService change', () {
      var notified = false;
      repo.addListener(() => notified = true);

      service.notifyListeners();

      expect(notified, isTrue);
    });
  });

  group('updateMatrixService', () {
    test('swaps internal reference', () {
      when(mockClient.userID).thenReturn('@me:example.com');
      expect(repo.userId, '@me:example.com');

      final service2 = MatrixService(
        client: mockClient,
        storage: mockStorage,
        clientName: 'test2',
      );
      repo.updateMatrixService(service2);

      when(mockClient.userID).thenReturn('@other:example.com');
      expect(repo.userId, '@other:example.com');
    });
  });

  group('dispose', () {
    test('does not notify after dispose', () {
      var notified = false;
      repo.addListener(() => notified = true);

      repo.dispose();
      notified = false;
      service.notifyListeners();

      expect(notified, isFalse);
    });
  });
}

class _FakeDatabase extends Fake implements DatabaseApi {
  @override
  Future<Map<String, dynamic>?> getClient(String name) async => null;

  @override
  Future<List<Event>> getEventList(
    Room room, {
    int start = 0,
    bool onlySending = false,
    int? limit,
  }) async =>
      <Event>[];
}
