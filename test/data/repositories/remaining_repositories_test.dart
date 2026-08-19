import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/data/repositories/auth_repository.dart';
import 'package:kohera/data/repositories/key_backup_repository.dart';
import 'package:kohera/data/repositories/media_repository.dart';
import 'package:kohera/data/repositories/message_search_repository.dart';
import 'package:kohera/data/repositories/outbox_repository.dart';
import 'package:kohera/data/repositories/push_rule_repository.dart';
import 'package:kohera/data/repositories/space_repository.dart';
import 'package:kohera/data/repositories/sticker_pack_repository.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/mockito.dart';

import '../../services/matrix_service_test.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockClient mockClient;
  late MockFlutterSecureStorage mockStorage;
  late MatrixService service;

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
  });

  group('AuthRepository', () {
    test('isLoggedIn delegates to MatrixService', () {
      final repo = AuthRepository(matrix: service);
      expect(repo.isLoggedIn, service.isLoggedIn);
      repo.dispose();
    });

    test('notifies on MatrixService change', () {
      final repo = AuthRepository(matrix: service);
      var notified = false;
      repo.addListener(() => notified = true);
      service.notifyListeners();
      expect(notified, isTrue);
      repo.dispose();
    });
  });

  group('KeyBackupRepository', () {
    test('chatBackup delegates to MatrixService', () {
      final repo = KeyBackupRepository(matrix: service);
      expect(repo.chatBackup, service.chatBackup);
      repo.dispose();
    });

    test('keyMirror delegates to MatrixService', () {
      final repo = KeyBackupRepository(matrix: service);
      expect(repo.keyMirror, service.keyMirror);
      repo.dispose();
    });
  });

  group('MediaRepository', () {
    test('avatarResolver delegates to MatrixService', () {
      final repo = MediaRepository(matrix: service);
      expect(repo.avatarResolver, service.avatarResolver);
      repo.dispose();
    });

    test('mediaResolver delegates to MatrixService', () {
      final repo = MediaRepository(matrix: service);
      expect(repo.mediaResolver, service.mediaResolver);
      repo.dispose();
    });
  });

  group('SpaceRepository', () {
    test('spaceAccess delegates to MatrixService', () {
      final repo = SpaceRepository(matrix: service);
      expect(repo.spaceAccess, service.spaceAccess);
      repo.dispose();
    });
  });

  group('OutboxRepository', () {
    test('outbox delegates to MatrixService', () {
      final repo = OutboxRepository(matrix: service);
      expect(repo.outbox, service.outbox);
      repo.dispose();
    });
  });

  group('PushRuleRepository', () {
    test('callPushRuleManager delegates to MatrixService', () {
      final repo = PushRuleRepository(matrix: service);
      expect(repo.callPushRuleManager, service.callPushRuleManager);
      repo.dispose();
    });

    test('globalPushRuleManager delegates to MatrixService', () {
      final repo = PushRuleRepository(matrix: service);
      expect(repo.globalPushRuleManager, service.globalPushRuleManager);
      repo.dispose();
    });
  });

  group('StickerPackRepository', () {
    test('stickerPacks delegates to MatrixService', () {
      final repo = StickerPackRepository(matrix: service);
      expect(repo.stickerPacks, service.stickerPacks);
      repo.dispose();
    });
  });

  group('MessageSearchRepository', () {
    test('messageIndexer delegates to MatrixService', () {
      final repo = MessageSearchRepository(matrix: service);
      expect(repo.messageIndexer, service.messageIndexer);
      repo.dispose();
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
