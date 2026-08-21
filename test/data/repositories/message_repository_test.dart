import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/account_session.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/data/repositories/message_repository.dart';
import 'package:kohera/data/services/matrix_client_service.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/utils/cached_stream_controller.dart';
import 'package:mockito/mockito.dart';

import '../../services/matrix_service_test.mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockClient mockClient;
  late MockFlutterSecureStorage mockStorage;
  late MatrixService service;
  late MessageRepository repo;

  setUp(() {
    mockClient = MockClient();
    mockStorage = MockFlutterSecureStorage();
    when(mockClient.rooms).thenReturn([]);
    when(mockClient.onSync).thenReturn(CachedStreamController<SyncUpdate>());
    when(mockClient.onPresenceChanged)
        .thenReturn(CachedStreamController<CachedPresence>());
    when(mockClient.database).thenReturn(_FakeDatabase());
    service = MatrixService(
      accountSession: AccountSession(matrixClientService: MatrixClientService(mockClient)),
      storage: mockStorage,
      clientName: 'test',
    );
    repo = MessageRepository(clientService: service.matrixClientService, messageIndexer: service.messageIndexer);
  });

  group('messageIndexer', () {
    test('returns MatrixService messageIndexer', () {
      expect(repo.messageIndexer, isNotNull);
    });
  });

  group('timelineFor', () {
    test('returns null for unknown room', () async {
      when(mockClient.getRoomById('!unknown:example.com')).thenReturn(null);
      expect(await repo.timelineFor('!unknown:example.com'), isNull);
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
