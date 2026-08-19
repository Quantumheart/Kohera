import 'package:flutter_test/flutter_test.dart';
import 'package:kohera/core/services/matrix_service.dart';
import 'package:kohera/data/repositories/message_repository.dart';
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
      client: mockClient,
      storage: mockStorage,
      clientName: 'test',
    );
    repo = MessageRepository(matrix: service);
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
      var notified = false;
      repo.addListener(() => notified = true);

      final service2 = MatrixService(
        client: mockClient,
        storage: mockStorage,
        clientName: 'test2',
      );
      repo.updateMatrixService(service2);

      notified = false;
      service2.notifyListeners();
      expect(notified, isTrue);

      notified = false;
      service.notifyListeners();
      expect(notified, isFalse);
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
